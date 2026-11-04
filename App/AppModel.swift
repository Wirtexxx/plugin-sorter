import AppKit
import Combine
import UniformTypeIdentifiers

enum CatalogFilter: Hashable {
    case all, problems, notInFL, new, duplicates, disabled
    /// Plugins with this tag of the user's.
    case tag(String)
}

enum CatalogSort {
    case name, size
}

/// The result of an action, shown above the list. Kept as the library's status so it is put
/// into words in the language the window shows.
struct Banner: Identifiable {
    enum Source {
        case sorter(Status), pictures(FLStatus), manager(ManagerStatus), favorites(FavoritesStatus)
    }

    let id = UUID()
    let source: Source
    let isError: Bool
    let undo: (() -> Void)?
}

/// State of the one-screen window. The four libraries keep doing the work; this joins their results
/// into rows, filters them and reports what happened.
final class AppModel: ObservableObject {
    let sorter: Sorter
    let manager: ManagerLibrary
    let favorites: FavoritesLibrary
    let pictures: FLLibrary
    let labels: UserLabels
    let vault: LicenseVault

    @Published var query = ""
    @Published var filter: CatalogFilter = .all
    @Published var sort: CatalogSort = .name
    @Published var expanded: String?
    /// The tab of a plugin's details, kept from one plugin to the next.
    @Published var detailsTab: DetailsTab = .files
    @Published var banner: Banner?
    /// Keys of the plugins installed since the last "all seen".
    @Published private(set) var newKeys: Set<String> = []
    @Published var showFolderSheet = false
    @Published var showCleanupSheet = false
    /// The plugin whose removal window is open.
    @Published var uninstallTarget: ManagedPlugin?
    /// "Don't ask again" in the FL dialog, until the app quits.
    var skipFLCheck = false
    /// FL's plugin database; a demo folder for README screenshots.
    var flRoot = FLDatabase.root

    private let known: KnownPlugins
    private var bag: Set<AnyCancellable> = []
    private var bannerTimer: Timer?
    /// `allRows`, kept until a library it's made from changes.
    private var cachedRows: [CatalogRow]?
    /// `findings`, kept until the installed plugins change.
    private var cachedFindings: [CleanupFinding]?
    /// FL's pictures by favourite file, kept until they change: every card asks on every redraw.
    private var cachedPictures: [String: FLPlugin]?

    init(sorter: Sorter = Sorter(), manager: ManagerLibrary = ManagerLibrary(),
         favorites: FavoritesLibrary = FavoritesLibrary(), pictures: FLLibrary = FLLibrary(),
         known: KnownPlugins = KnownPlugins(), labels: UserLabels = UserLabels(),
         vault: LicenseVault = LicenseVault(store: KeychainStore(service: LicenseVault.service))) {
        self.vault = vault
        self.known = known
        self.labels = labels
        self.sorter = sorter
        self.manager = manager
        self.favorites = favorites
        self.pictures = pictures

        // Any change in a library redraws the window
        for publisher in [sorter.objectWillChange, manager.objectWillChange,
                          favorites.objectWillChange, pictures.objectWillChange, labels.objectWillChange] {
            publisher.receive(on: RunLoop.main).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        }
        // Right away, not on the next run loop pass: a redraw must never see rows older than the data
        let forget: (Any) -> Void = { [weak self] _ in self?.cachedRows = nil }
        manager.$plugins.sink(receiveValue: forget).store(in: &bag)
        manager.$plugins.sink { [weak self] _ in self?.cachedFindings = nil }.store(in: &bag)
        manager.$plugins.sink { [weak self] plugins in
            guard let self = self else { return }
            self.newKeys = self.known.update(with: plugins)
        }.store(in: &bag)
        favorites.$entries.sink(receiveValue: forget).store(in: &bag)
        favorites.$favorites.sink(receiveValue: forget).store(in: &bag)
        favorites.$availability.sink(receiveValue: forget).store(in: &bag)
        pictures.$plugins.sink { [weak self] _ in self?.cachedPictures = nil }.store(in: &bag)
        // A tag filter whose last plugin lost the tag would be an empty list with no way out
        labels.$all.dropFirst().sink { [weak self] all in
            guard let self = self, case .tag(let tag) = self.filter else { return }
            let used = all.values.contains { $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
            if !used { self.filter = .all }
        }.store(in: &bag)
        observeStatuses()
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &bag)
    }

    // MARK: - Rows

    /// Asked for several times per redraw (the list and each filter's count), so built once.
    var allRows: [CatalogRow] {
        if let rows = cachedRows { return rows }
        let removed = Set(favorites.availability.filter { $0.value == .removed }.map(\.key))
        let rows = PluginCatalog.rows(plugins: manager.plugins, entries: favorites.entries,
                                      favorites: favorites.favorites, removed: removed)
        cachedRows = rows
        return rows
    }

    /// Old versions and duplicates among the installed plugins; asked for on every redraw, so built once.
    var findings: [CleanupFinding] {
        if let findings = cachedFindings { return findings }
        let findings = Cleanup.findings(manager.plugins)
        cachedFindings = findings
        return findings
    }

    /// Space the finding's files take.
    func size(of finding: CleanupFinding) -> Int64 { finding.bundles.reduce(0) { $0 + (manager.sizes[$1.path] ?? 0) } }

    var rows: [CatalogRow] {
        let matching = allRows.filter { row in
            passes(row, filter)
                && (query.isEmpty || row.name.localizedCaseInsensitiveContains(query)
                    || row.vendor.localizedCaseInsensitiveContains(query)
                    || tags(of: row).contains { $0.localizedCaseInsensitiveContains(query) })
        }
        guard sort == .size else { return matching }
        return matching.sorted { size(of: $0) > size(of: $1) }
    }

    /// The list as it is on screen now, with the search and the filter applied.
    func exportRows() -> [ExportRow] {
        rows.map { ExportRow(row: $0, level: level(of: $0), sizeBytes: size(of: $0), tags: tags(of: $0)) }
    }

    /// Asks where to save the visible list and writes it there.
    func export(as format: ExportFormat) {
        let rows = exportRows()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Plugins." + format.rawValue
        if let type = UTType(filenameExtension: format.rawValue) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CatalogExport.render(rows, as: format).write(to: url, atomically: true, encoding: .utf8)
            show(Banner(source: .manager(.exported(rows.count)), isError: false, undo: nil))
        } catch {
            show(Banner(source: .manager(.failed(error.localizedDescription)), isError: true, undo: nil))
        }
    }

    /// The user's tags of the row's plugin.
    func tags(of row: CatalogRow) -> [String] { row.plugin.map { labels.labels(of: $0.key).tags } ?? [] }

    func labelColor(of row: CatalogRow) -> LabelColor? { row.plugin.flatMap { labels.labels(of: $0.key).color } }

    func isNew(_ row: CatalogRow) -> Bool { row.plugin.map { newKeys.contains($0.key) } ?? false }

    /// "All seen": the marks go and the list leaves the filter that has nothing left to show.
    func markAllSeen() {
        known.markAllSeen()
        newKeys = []
        if filter == .new { filter = .all }
    }

    func count(_ filter: CatalogFilter) -> Int { allRows.filter { passes($0, filter) }.count }

    func level(of row: CatalogRow) -> CheckState.Level? {
        if row.isStale { return .failed }
        return row.plugin.flatMap(manager.level)
    }

    func size(of row: CatalogRow) -> Int64 { row.plugin.map(manager.size) ?? 0 }

    private func passes(_ row: CatalogRow, _ filter: CatalogFilter) -> Bool {
        switch filter {
        case .all:               return true
        case .problems:          return (level(of: row) ?? .ok) > .ok
        case .notInFL:           return !row.isFavorite && !row.isStale
        case .disabled:          return row.plugin?.isDisabled ?? false
        case .duplicates:        return row.plugin.map { plugin in findings.contains { $0.pluginKey == plugin.key } } ?? false
        case .new:               return isNew(row)
        case .tag(let tag):      return tags(of: row).contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
    }

    // MARK: - Actions

    /// Rescans everything; called at launch, after actions and when the app comes back to the front.
    func refresh() {
        guard !Helper.isHelper() else { return }
        manager.scan()
        favorites.scan()
        pictures.scan()
        sorter.refreshLatestLog()
        sorter.preview(keepStatus: true)
    }

    /// Runs an FL change now, or asks first while FL Studio is open.
    func whenFLClosed(_ action: @escaping () -> Void) {
        guard !skipFLCheck, FLStudio.isRunning else { return action() }
        let t = L10n(lang: Lang(rawValue: UserDefaults.standard.string(forKey: "language") ?? Lang.system.rawValue) ?? .en)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t("flOpen.title")
        alert.informativeText = t("flOpen.text")
        alert.addButton(withTitle: t("flOpen.continue"))
        alert.addButton(withTitle: t("mgr.cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = t("flOpen.dontAsk")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if alert.suppressionButton?.state == .on { skipFLCheck = true }
        action()
    }

    // MARK: - Licenses

    /// Shows a failed Keychain call above the list. The user closing the password dialog is not one.
    func report(_ error: Error) {
        if let error = error as? SecretStoreError, error == .cancelled { return }
        show(Banner(source: .manager(.failed(error.localizedDescription)), isError: true, undo: nil))
    }

    /// Puts a secret on the pasteboard and takes it off after a minute, if nothing else was copied since.
    func copySecret(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let count = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.secretLifetime) {
            if pasteboard.changeCount == count { pasteboard.clearContents() }
        }
    }

    static let secretLifetime: TimeInterval = 60

    // MARK: - Tasks

    /// Third-party favourites that are FL's plugin picks; stock ones aren't ours to sort or picture.
    var pictureTargets: [FLPlugin] { pictures.plugins.filter { !$0.isStock } }
    var missingPictures: [FLPlugin] { pictures.missing.filter { !$0.isStock } }
    var categoryTotal: Int { favorites.favorites.filter { !$0.isStock }.count }

    /// Nothing left in any task. False until everything is read: every count is 0 before that.
    /// `sorter.running` is left out because each return to the window runs a preview.
    var tasksAllDone: Bool {
        sorter.loaded && favorites.loaded && pictures.loaded
            && (sorter.applied || sorter.moves.isEmpty)
            && favorites.unsorted.isEmpty && missingPictures.isEmpty
            && !favorites.busy && !pictures.busy
    }

    // MARK: - FL for one row

    /// Formats in the order a star picks them, as in the favourites list.
    private static let preference = ["VST3", "CLAP", "AudioUnit", "VST"]

    /// The section FL files the plugin under, "Effects" or "Generators".
    func section(of row: CatalogRow) -> String {
        row.favorites.first?.section ?? row.entries.first?.section ?? "Effects"
    }

    /// The FL category folder of the plugin's favourite, nil at the top of its section.
    func category(of row: CatalogRow) -> String? {
        row.favorites.lazy.compactMap { FLCategories.folder(of: $0, root: self.flRoot) }.first
    }

    /// The picture FL shows for the plugin's favourite.
    func picture(of row: CatalogRow) -> FLPlugin? {
        let index: [String: FLPlugin]
        if let cached = cachedPictures {
            index = cached
        } else {
            index = Dictionary(pictures.plugins.map { ($0.fst.path, $0) }, uniquingKeysWith: { first, _ in first })
            cachedPictures = index
        }
        return row.favorites.lazy.compactMap { index[$0.fst.path] }.first
    }

    func isFavorite(_ entry: InstalledEntry) -> Bool { favorites.isFavorite(entry) }

    /// A click on the star.
    func tapStar(_ row: CatalogRow) {
        switch StarTap(row: row, busy: favorites.busy) {
        case .toggle: toggleFavorite(row)
        case .notSeen: show(Banner(source: .manager(.notSeenByFL), isError: true, undo: nil))
        case .wait: break
        }
    }

    /// The star: removes every favourite of the plugin, or adds its preferred format.
    private func toggleFavorite(_ row: CatalogRow) {
        whenFLClosed {
            if row.isFavorite {
                self.favorites.remove(row.favorites)
            } else if let entry = self.preferred(row) {
                self.favorites.toggle(entry, added: self.adoptShot(of: row))
            }
        }
    }

    /// A format pill in the details: that one format in or out of the favourites.
    func toggle(_ entry: InstalledEntry) {
        let row = allRows.first { $0.entries.contains { $0.id == entry.id } }
        whenFLClosed { self.favorites.toggle(entry, added: row.flatMap(self.adoptShot)) }
    }

    /// Hands the plugin's screenshot to its new favourite, when the app has one.
    private func adoptShot(of row: CatalogRow) -> ((URL) -> Void)? {
        guard let shot = row.plugin.flatMap({ pictures.localPicture(of: $0.key) }) else { return nil }
        return { [weak self] fst in self?.pictures.adopt(shot, for: fst) }
    }

    /// What the card shows: FL's picture, or our screenshot, which beats a generated card in FL.
    func artwork(of row: CatalogRow) -> (url: URL, hasHeader: Bool)? {
        let shot = row.plugin.flatMap { pictures.localPicture(of: $0.key) }
        if let picture = picture(of: row), picture.hasPicture, picture.source != .card || shot == nil {
            return (picture.picture, picture.source != nil)
        }
        return shot.map { ($0, false) }
    }

    /// Plugins still without a real picture, which a capture of everything would open.
    var shotTargets: [ManagedPlugin] {
        let pictured = allRows.filter { row in
            picture(of: row).map { $0.hasPicture && $0.source != .card } ?? false
        }.compactMap { $0.plugin?.key }
        return LocalPictures.targets(manager.plugins, skipping: pictures.localKeys.union(pictured))
    }

    func captureAllPictures() { pictures.captureAll(shotTargets) }

    /// The pictures task: favourites with a screenshot of ours get it without opening the plugin.
    func addMissingPictures() {
        var shots: [String: URL] = [:]
        for row in allRows {
            guard let shot = row.plugin.flatMap({ pictures.localPicture(of: $0.key) }) else { continue }
            for favorite in row.favorites { shots[favorite.id] = shot }
        }
        let targets = missingPictures
        whenFLClosed { self.pictures.generate(targets, screenshots: true, local: shots) }
    }

    func setCategory(_ row: CatalogRow, to folder: String?) {
        let favoriteRow = FavoriteRow(key: row.id, name: row.name, vendor: row.vendor,
                                      section: section(of: row), entries: row.entries)
        whenFLClosed { self.favorites.setCategory(favoriteRow, to: folder) }
    }

    private func preferred(_ row: CatalogRow) -> InstalledEntry? {
        let usable = row.entries.filter { favorites.availability[$0.id] != .removed }
        let rank = { (entry: InstalledEntry) in Self.preference.firstIndex(of: entry.format) ?? Self.preference.count }
        return (usable.isEmpty ? row.entries : usable).min { rank($0) < rank($1) }
    }

    private func observeStatuses() {
        sorter.$status.dropFirst().sink { [weak self] status in
            guard let self = self else { return }
            switch status {
            case .moved, .undone, .auRestored:
                self.manager.scan()
                self.sorter.preview(keepStatus: true)
                fallthrough
            case .cancelled:
                let undo: (() -> Void)? = { if case .moved = status { return { self.sorter.undo() } }; return nil }()
                self.show(Banner(source: .sorter(status), isError: false, undo: undo))
            case .partlyMoved(let moved, _):
                self.manager.scan()
                self.sorter.preview(keepStatus: true)
                self.show(Banner(source: .sorter(status), isError: true, undo: moved > 0 ? { self.sorter.undo() } : nil))
            case .undoIncomplete:
                self.manager.scan()
                self.show(Banner(source: .sorter(status), isError: true, undo: { self.sorter.undo() }))
            case .failed:
                self.show(Banner(source: .sorter(status), isError: true, undo: nil))
            case .idle, .noFormats, .willMove:
                break
            }
        }.store(in: &bag)

        favorites.$status.dropFirst().sink { [weak self] status in
            guard let self = self, status != .idle else { return }
            var isError = false
            if case .failed = status { isError = true }
            let undo: (() -> Void)? = {
                if case .sorted = status { return { self.whenFLClosed { self.favorites.unsort() } } }
                return nil
            }()
            self.show(Banner(source: .favorites(status), isError: isError, undo: undo))
        }.store(in: &bag)

        pictures.$status.dropFirst().sink { [weak self] status in
            guard let self = self, status != .idle else { return }
            var isError = false
            if case .failed = status { isError = true }
            self.show(Banner(source: .pictures(status), isError: isError, undo: nil))
        }.store(in: &bag)

        manager.$status.dropFirst().sink { [weak self] status in
            guard let self = self, status != .idle else { return }
            var isError = false
            if case .failed = status { isError = true }
            self.show(Banner(source: .manager(status), isError: isError, undo: nil))
        }.store(in: &bag)
    }

    private func show(_ banner: Banner) {
        self.banner = banner
        bannerTimer?.invalidate()
        // Results with an undo stay until closed; the rest fade on their own
        guard banner.undo == nil else { return }
        bannerTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            if self?.banner?.id == banner.id { self?.banner = nil }
        }
    }
}
