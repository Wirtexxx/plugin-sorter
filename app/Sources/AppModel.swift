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

    enum Tone { case success, info, error }

    let id = UUID()
    let source: Source
    let isError: Bool
    let undo: (() -> Void)?

    /// A cancel and a hint are neither a success nor a failure.
    var tone: Tone {
        if isError { return .error }
        switch source {
        case .sorter(.cancelled), .manager(.cancelled), .manager(.notSeenByFL): return .info
        default: return .success
        }
    }

    /// Errors stay until read, and results with an undo until decided on.
    var fades: Bool { !isError && undo == nil }
}

/// What the model needs from the world around it, and from the person in front of it.
struct Dialogs {
    enum Answer { case cancel, proceed, continueAndDontAsk }

    var hostsRunning: () -> [String] = { HostApps.running }
    var flRunning: () -> Bool = { FLStudio.isRunning }
    /// Title and text of a warning that can be silenced until the app quits.
    var ask: (String, String) -> Answer = Dialogs.alert

    private static func alert(_ title: String, _ text: String) -> Answer {
        let t = L10n(lang: Lang(rawValue: UserDefaults.standard.string(forKey: "language") ?? Lang.system.rawValue) ?? .en)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: t("flOpen.continue"))
        alert.addButton(withTitle: t("mgr.cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = t("flOpen.dontAsk")
        guard alert.runModal() == .alertFirstButtonReturn else { return .cancel }
        return alert.suppressionButton?.state == .on ? .continueAndDontAsk : .proceed
    }
}

/// All a row shows, compared to tell whether it has to be drawn again. The rest of the window can change
/// as much as it likes: a check moving on to the next plugin touches two rows, not all of them.
struct RowState: Equatable {
    struct Pill: Equatable {
        let text: String
        let level: CheckState.Level?
    }

    let id: String
    let name: String
    let vendor: String
    let lang: Lang
    let isStale: Bool
    let isDisabled: Bool
    let level: CheckState.Level?
    let running: Bool
    let isNew: Bool
    let pills: [Pill]
    let isFavorite: Bool
    let isKnownToFL: Bool
    let category: String?
    let size: Int64
    let color: LabelColor?
    let isExpanded: Bool
    let usesFL: Bool
    let favoritesBusy: Bool
    let pictureURL: URL?
    let pictureHasHeader: Bool
    let picturesBusy: Bool
    /// What the row's buttons act on.
    let entries: [String]
    let favorites: [String]
}

/// Why the list has nothing to show.
enum EmptyList: Equatable {
    case noMatches, noPlugins

    init(query: String, filter: CatalogFilter, plugins: Int) {
        self = !query.isEmpty || filter != .all || plugins > 0 ? .noMatches : .noPlugins
    }
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
    var flRoot = FLDatabase.root { didSet { findFL() } }
    /// FL's database is on this Mac.
    @Published private var flFound = FLDatabase.exists
    /// Whether to show anything about FL: without it those columns and tasks would only say "done".
    var usesFL: Bool { flFound || !favorites.entries.isEmpty }
    /// "Don't ask again" in the dialog about open hosts, until the app quits.
    var skipHostCheck = false

    private let known: KnownPlugins
    private var bag: Set<AnyCancellable> = []
    private var bannerTimer: Timer?
    /// The plugin of the uninstall running now.
    private var uninstalling: String?
    private let refreshes = Debouncer(delay: 0.3)
    var dialogs = Dialogs()
    /// `allRows`, kept until a library it's made from changes.
    private var cachedRows: [CatalogRow]?
    /// `rows` and the filters' counts, kept until something they depend on changes.
    private var cachedVisible: [CatalogRow]?
    private var cachedCounts: [CatalogFilter: Int] = [:]
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
        let forget: (Any) -> Void = { [weak self] _ in
            self?.cachedRows = nil
            self?.forgetVisible()
        }
        let forgetList: (Any) -> Void = { [weak self] _ in self?.forgetVisible() }
        manager.$results.sink(receiveValue: forgetList).store(in: &bag)
        manager.$sizes.sink(receiveValue: forgetList).store(in: &bag)
        labels.$all.sink(receiveValue: forgetList).store(in: &bag)
        $query.sink(receiveValue: forgetList).store(in: &bag)
        $filter.sink(receiveValue: forgetList).store(in: &bag)
        $sort.sink(receiveValue: forgetList).store(in: &bag)
        $newKeys.sink(receiveValue: forgetList).store(in: &bag)
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
        labels.$saveError.compactMap { $0 }.sink { [weak self] error in
            self?.show(Banner(source: .manager(.failed(error)), isError: true, undo: nil))
        }.store(in: &bag)
        observeStatuses()
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.scheduleRefresh() }
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

    private func forgetVisible() {
        cachedVisible = nil
        cachedCounts = [:]
    }

    /// The list as it is on screen. Asked for several times per redraw.
    var rows: [CatalogRow] {
        if let rows = cachedVisible { return rows }
        let rows = visibleRows()
        cachedVisible = rows
        return rows
    }

    private func visibleRows() -> [CatalogRow] {
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

    func count(_ filter: CatalogFilter) -> Int {
        if let count = cachedCounts[filter] { return count }
        let count = allRows.filter { passes($0, filter) }.count
        cachedCounts[filter] = count
        return count
    }

    func state(of row: CatalogRow) -> RowState {
        let bundles = row.plugin?.bundles ?? []
        let art = artwork(of: row)
        return RowState(id: row.id, name: row.name, vendor: row.vendor, lang: currentLanguage, isStale: row.isStale,
                        isDisabled: row.plugin?.isDisabled ?? false, level: level(of: row),
                        running: bundles.contains { manager.state(of: $0) == .running }, isNew: isNew(row),
                        pills: bundles.map { RowState.Pill(text: $0.format.rawValue, level: manager.state(of: $0).level) },
                        isFavorite: row.isFavorite, isKnownToFL: row.isKnownToFL, category: category(of: row),
                        size: size(of: row), color: labelColor(of: row), isExpanded: expanded == row.id, usesFL: usesFL,
                        favoritesBusy: favorites.busy, pictureURL: art?.url, pictureHasHeader: art?.hasHeader ?? false,
                        picturesBusy: pictures.busy, entries: row.entries.map(\.id), favorites: row.favorites.map(\.id))
    }

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

    /// A refresh when things have calmed down. The window coming to the front is often a side effect of
    /// our own work: the password dialog closing, a helper that took the focus for a screenshot going away.
    /// What runs then reports back with a scan of its own.
    func scheduleRefresh() {
        guard !sorter.running, !manager.busy, !pictures.capturingAll else { return }
        refreshes.schedule { [weak self] in self?.refresh() }
    }

    /// Rescans everything.
    func refresh() {
        guard !Helper.isHelper() else { return }
        findFL()
        manager.scan()
        favorites.scan()
        pictures.scan()
        sorter.refreshLatestLog()
        sorter.preview(keepStatus: true)
    }

    private func findFL() {
        let found = FileManager.default.fileExists(atPath: flRoot.path)
        if found != flFound { flFound = found }
    }

    /// Goes back to every plugin, from a search or filter that found nothing.
    func clearFilters() {
        query = ""
        filter = .all
    }

    /// Runs a change to plugin files now, or asks first while a host that may have them loaded is open.
    func whenHostsClosed(_ action: @escaping () -> Void) {
        let hosts = dialogs.hostsRunning()
        guard !skipHostCheck, !hosts.isEmpty else { return action() }
        let t = L10n(lang: currentLanguage)
        switch dialogs.ask(t("hosts.title", hosts.joined(separator: ", ")), t("hosts.text")) {
        case .cancel:             return
        case .proceed:            action()
        case .continueAndDontAsk: skipHostCheck = true; action()
        }
    }

    func sortFolders() { whenHostsClosed { self.sorter.apply() } }

    func undoSort() { whenHostsClosed { self.sorter.undo() } }

    /// Runs an FL change now, or asks first while FL Studio is open.
    func whenFLClosed(_ action: @escaping () -> Void) {
        guard !skipFLCheck, dialogs.flRunning() else { return action() }
        let t = L10n(lang: currentLanguage)
        switch dialogs.ask(t("flOpen.title"), t("flOpen.text")) {
        case .cancel:             return
        case .proceed:            action()
        case .continueAndDontAsk: skipFLCheck = true; action()
        }
    }

    private var currentLanguage: Lang {
        Lang(rawValue: UserDefaults.standard.string(forKey: "language") ?? Lang.system.rawValue) ?? .en
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
        guard sorter.loaded, sorter.applied || sorter.moves.isEmpty else { return false }
        guard usesFL else { return true }
        return favorites.loaded && pictures.loaded && favorites.unsorted.isEmpty && missingPictures.isEmpty
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
        case .notSeen: show(Banner(source: .manager(.notSeenByFL), isError: false, undo: nil))
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
        let failed = pictures.failedKeys(among: manager.plugins)
        return LocalPictures.targets(manager.plugins, skipping: pictures.localKeys.union(pictured).union(failed))
    }

    /// Waves favourites a capture of everything photographs straight into FL, each through its own Audio Unit.
    var wavesShots: [FLPlugin] { pictures.plugins.filter(\.needsWavesShot) }

    /// Plugins that wouldn't open last time and are left out of a capture until asked for.
    var failedShots: Int { pictures.failedKeys(among: manager.plugins).count }

    /// The shared database first, then a capture of whatever it didn't have.
    func captureAllPictures() {
        var wanted = Dictionary(shotTargets.map { ($0.key, $0.pictureKeys) }, uniquingKeysWith: { a, _ in a })
        for waves in wavesShots { wanted[PictureKey.waves(waves.title)] = [PictureKey.waves(waves.title)] }
        wanted.merge(pictures.downloadedPictures(among: manager.plugins)) { a, _ in a }
        guard !wanted.isEmpty else { return }
        pictures.fetchFromDatabase(wanted) { self.captureRemainingPictures() }
    }

    /// Waves favourites with a picture of ours, by favourite: they go into FL without opening a plugin.
    private func wavesPictures(_ waves: [FLPlugin]) -> [String: URL] {
        var shots: [String: URL] = [:]
        for plugin in waves where FLFavorites.normalize(plugin.info.vendor) == "waves" {
            shots[plugin.id] = pictures.localPicture(of: PictureKey.waves(plugin.title))
        }
        return shots
    }

    /// Asks first: the plugins' windows take over the screen for a while.
    private func captureRemainingPictures() {
        let targets = shotTargets
        let waves = wavesShots
        let wavesLocal = wavesPictures(waves)
        let wavesToOpen = waves.filter { wavesLocal[$0.id] == nil }
        guard !targets.isEmpty || !wavesToOpen.isEmpty else {
            // Everything came from the database: nothing to open, only FL to fill
            if !waves.isEmpty { whenFLClosed { self.pictures.generate(waves, screenshots: false, local: wavesLocal) } }
            return
        }
        let t = L10n(lang: currentLanguage)
        let alert = NSAlert()
        alert.messageText = t("capture.confirm", targets.count + wavesToOpen.count)
        alert.informativeText = t("capture.confirmInfo")
        alert.addButton(withTitle: t("capture.start"))
        alert.addButton(withTitle: t("mgr.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard !waves.isEmpty else { return pictures.captureAll(targets) }
        whenFLClosed {
            self.pictures.captureAll(targets) { self.pictures.generate(waves, screenshots: true, local: wavesLocal) }
        }
    }

    /// Shown only with `defaults write io.github.wirtexxx.plugin-sorter authorTools -bool YES`.
    var showsAuthorTools: Bool { UserDefaults.standard.bool(forKey: "authorTools") }

    /// The author fills the shared picture database: pick the local copy of its repository.
    func exportPicturesForDatabase() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n(lang: currentLanguage)("gear.exportPictures")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let plugins = LocalPictures.targets(manager.plugins, skipping: [])
        let waves = pictures.plugins.filter { FLFavorites.normalize($0.info.vendor) == "waves" }
        pictures.exportForDatabase(plugins, waves: waves, into: folder)
    }

    func retryFailedPictures() {
        pictures.forgetFailedShots()
        captureAllPictures()
    }

    /// Removes a plugin for good, and with it the screenshot only it could use.
    func uninstall(_ plugin: ManagedPlugin, leftovers: [Leftover], receipts: [Receipt]) {
        uninstalling = plugin.key
        manager.uninstall(plugin, leftovers: leftovers, receipts: receipts)
    }

    /// The pictures task: the shared database first, then favourites with a picture of ours get it
    /// without opening the plugin, and only the rest are opened.
    func addMissingPictures() {
        let missing = Set(missingPictures.map(\.id))
        var wanted: [String: [String]] = [:]
        for row in allRows where row.favorites.contains(where: { missing.contains($0.id) }) {
            if let plugin = row.plugin, !plugin.isWaveShell { wanted[plugin.key] = plugin.pictureKeys }
        }
        for plugin in missingPictures where FLFavorites.normalize(plugin.info.vendor) == "waves" {
            wanted[PictureKey.waves(plugin.title)] = [PictureKey.waves(plugin.title)]
        }
        wanted.merge(pictures.downloadedPictures(among: manager.plugins)) { a, _ in a }
        pictures.fetchFromDatabase(wanted) { self.addPicturesToFL() }
    }

    private func addPicturesToFL() {
        let targets = missingPictures
        var shots = wavesPictures(targets)
        for row in allRows {
            guard let shot = row.plugin.flatMap({ pictures.localPicture(of: $0.key) }) else { continue }
            for favorite in row.favorites { shots[favorite.id] = shot }
        }
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
            case .moved, .undone:
                self.manager.scan()
                self.sorter.preview(keepStatus: true)
                fallthrough
            case .cancelled:
                let undo: (() -> Void)? = { if case .moved = status { return { self.undoSort() } }; return nil }()
                self.show(Banner(source: .sorter(status), isError: false, undo: undo))
            case .partlyMoved(let moved, _):
                self.manager.scan()
                self.sorter.preview(keepStatus: true)
                self.show(Banner(source: .sorter(status), isError: true, undo: moved > 0 ? { self.undoSort() } : nil))
            case .undoIncomplete:
                self.manager.scan()
                self.show(Banner(source: .sorter(status), isError: true, undo: { self.undoSort() }))
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
            if case .captured(_, let failed) = status {
                isError = !failed.isEmpty   // stays up: it names the plugins
                self.scheduleRefresh()
            }
            self.show(Banner(source: .pictures(status), isError: isError, undo: nil))
        }.store(in: &bag)

        manager.$status.dropFirst().sink { [weak self] status in
            guard let self = self, status != .idle else { return }
            var isError = false
            switch status {
            case .failed, .partly: isError = true
            case .trashed:
                if let key = self.uninstalling { self.pictures.removeLocalPicture(of: key) }
            default: break
            }
            self.uninstalling = nil
            self.show(Banner(source: .manager(status), isError: isError, undo: nil))
        }.store(in: &bag)
    }

    private func show(_ banner: Banner) {
        self.banner = banner
        bannerTimer?.invalidate()
        guard banner.fades else { return }
        bannerTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            if self?.banner?.id == banner.id { self?.banner = nil }
        }
    }
}
