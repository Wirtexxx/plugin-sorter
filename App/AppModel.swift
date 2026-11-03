import AppKit
import Combine

enum CatalogFilter: Hashable {
    case all, problems, notInFL, new, duplicates
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

    @Published var query = ""
    @Published var filter: CatalogFilter = .all
    @Published var sort: CatalogSort = .name
    @Published var expanded: String?
    @Published var banner: Banner?
    /// An FL change waiting for the user to confirm while FL Studio is open.
    @Published var confirmFL: (() -> Void)?
    /// "Don't ask again" in the FL dialog, until the app quits.
    var skipFLCheck = false
    /// FL's plugin database; a demo folder for README screenshots.
    var flRoot = FLDatabase.root

    private var bag: Set<AnyCancellable> = []
    private var bannerTimer: Timer?

    init(sorter: Sorter = Sorter(), manager: ManagerLibrary = ManagerLibrary(),
         favorites: FavoritesLibrary = FavoritesLibrary(), pictures: FLLibrary = FLLibrary()) {
        self.sorter = sorter
        self.manager = manager
        self.favorites = favorites
        self.pictures = pictures

        // Any change in a library redraws the window
        for publisher in [sorter.objectWillChange, manager.objectWillChange,
                          favorites.objectWillChange, pictures.objectWillChange] {
            publisher.receive(on: RunLoop.main).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        }
        observeStatuses()
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &bag)
    }

    // MARK: - Rows

    var allRows: [CatalogRow] {
        let removed = Set(favorites.availability.filter { $0.value == .removed }.map(\.key))
        return PluginCatalog.rows(plugins: manager.plugins, entries: favorites.entries,
                                  favorites: favorites.favorites, removed: removed)
    }

    var rows: [CatalogRow] {
        let matching = allRows.filter { row in
            passes(row, filter)
                && (query.isEmpty || row.name.localizedCaseInsensitiveContains(query)
                    || row.vendor.localizedCaseInsensitiveContains(query))
        }
        guard sort == .size else { return matching }
        return matching.sorted { size(of: $0) > size(of: $1) }
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
        case .notInFL:           return row.plugin != nil && !row.isFavorite
        case .new, .duplicates:  return false
        }
    }

    // MARK: - Actions

    /// Rescans everything; called at launch, after actions and when the app comes back to the front.
    func refresh() {
        manager.scan()
        favorites.scan()
        pictures.scan()
        sorter.refreshLatestLog()
        sorter.preview(keepStatus: true)
    }

    /// Runs an FL change now, or asks first while FL Studio is open.
    func whenFLClosed(_ action: @escaping () -> Void) {
        if skipFLCheck || !FLStudio.isRunning {
            action()
        } else {
            confirmFL = action
        }
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
        let paths = Set(row.favorites.map(\.fst.path))
        return pictures.plugins.first { paths.contains($0.fst.path) }
    }

    func isFavorite(_ entry: InstalledEntry) -> Bool { favorites.isFavorite(entry) }

    /// The star: removes every favourite of the plugin, or adds its preferred format.
    func toggleFavorite(_ row: CatalogRow) {
        whenFLClosed {
            if row.isFavorite {
                self.favorites.remove(row.favorites)
            } else if let entry = self.preferred(row) {
                self.favorites.toggle(entry)
            }
        }
    }

    /// A format pill in the details: that one format in or out of the favourites.
    func toggle(_ entry: InstalledEntry) {
        whenFLClosed { self.favorites.toggle(entry) }
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
            case .moved, .undone, .auRestored, .cancelled:
                let undo: (() -> Void)? = { if case .moved = status { return { self.sorter.undo() } }; return nil }()
                self.show(Banner(source: .sorter(status), isError: false, undo: undo))
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
            let undo: (() -> Void)? = { if case .sorted = status { return { self.favorites.unsort() } }; return nil }()
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
