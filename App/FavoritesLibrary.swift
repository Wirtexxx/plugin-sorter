import Foundation
import AVFoundation

/// One plugin as FL lists it, with every format FL scanned (VST3, AU, CLAP…).
struct FavoriteRow: Identifiable {
    var id: String { key }
    let key: String
    let name: String
    let vendor: String
    let section: String
    let entries: [InstalledEntry]

    var isNative: Bool { entries.contains(where: \.isNative) }
}

enum FavoritesStatus: Equatable {
    case idle
    case removed(Int)
    case restored(Int)
    case sorted(Int)
    case unsorted(Int)
    case failed(String)
}

/// A plugin file that can report its categories.
private struct TaggedBundle: Hashable {
    let format: PluginFormat
    let url: URL
}

/// State of the Favourites section: what FL scanned, what's in its browser, and what's gone.
final class FavoritesLibrary: ObservableObject {
    @Published private(set) var entries: [InstalledEntry] = []
    @Published private(set) var favorites: [Favorite] = [] {
        didSet { unsorted = Self.unsorted(in: favorites) }
    }
    /// What one click sorts: third-party favourites still at the top of Effects or Generators.
    /// Kept ready because the window reads it on every redraw.
    private(set) var unsorted: [Favorite] = []
    @Published private(set) var availability: [String: Availability] = [:]
    @Published var busy = false
    /// The first scan has finished, so the lists say what is really there.
    @Published private var scanned = false
    var loaded: Bool { demo || scanned }
    @Published var status: FavoritesStatus = .idle
    /// The plugin being read while sorting by category.
    @Published private(set) var current = ""

    private let backup = FavoriteBackup()
    private let journal = CategoryJournal()
    private let tags = TagCache()
    private let queue = DispatchQueue(label: "plugin-sorter.favorites", qos: .userInitiated)

    private var demo = false

    init() {}

    /// Fixed content for README screenshots; never touches FL's database.
    init(demoEntries: [InstalledEntry], favorites: [Favorite]) {
        demo = true
        entries = demoEntries
        self.favorites = favorites
        unsorted = Self.unsorted(in: favorites)
        for entry in demoEntries { availability[entry.id] = .available }
    }

    var canRestore: Bool { !backup.records.isEmpty }
    var canUnsort: Bool { !journal.moves.isEmpty }

    private static func unsorted(in favorites: [Favorite]) -> [Favorite] {
        favorites.filter { !$0.isStock && FLCategories.folder(of: $0) == nil }
    }

    func isFavorite(_ entry: InstalledEntry) -> Bool { favorites.contains { $0.entry?.id == entry.id } }

    func favorites(of row: FavoriteRow) -> [Favorite] {
        favorites.filter { fav in row.entries.contains { $0.id == fav.entry?.id } }
    }

    /// The category folder the plugin's favourites are in, nil at the top of the section.
    func category(of row: FavoriteRow) -> String? { favorites(of: row).lazy.compactMap { FLCategories.folder(of: $0) }.first }

    func availability(of row: FavoriteRow) -> Availability {
        let states = row.entries.map { availability[$0.id] ?? .unknown }
        if states.contains(.available) { return .available }
        if states.contains(.moved) { return .moved }
        return states.allSatisfy { $0 == .removed } ? .removed : .unknown
    }

    func scan() {
        guard !demo else { return }
        queue.async {
            let entries = FLFavorites.installed()
            let favorites = FLFavorites.favorites(installed: entries)
            let plugins = PluginInventory.scan()
            let bundleNames = Set(plugins.flatMap(\.bundles).map { $0.url.lastPathComponent })
            var audioUnits = Set(AVAudioUnitComponentManager.shared().components { _, _ in true }
                .map { FLFavorites.auKey(vendor: $0.manufacturerName, name: $0.name) })
            // A turned-off AU is gone from the registry but still installed; empty stays "unknown"
            if !audioUnits.isEmpty { audioUnits.formUnion(FLFavorites.disabledAudioUnitKeys(plugins)) }
            var availability: [String: Availability] = [:]
            for entry in entries {
                availability[entry.id] = FLFavorites.availability(entry, bundleNames: bundleNames, audioUnits: audioUnits)
            }
            DispatchQueue.main.async {
                self.entries = entries
                self.favorites = favorites
                self.availability = availability
                self.scanned = true
            }
        }
    }

    /// A format chip: adds or removes just that format.
    /// - Parameter added: gets the favourite's file when one was added.
    func toggle(_ entry: InstalledEntry, added: ((URL) -> Void)? = nil) {
        if isFavorite(entry) {
            remove(favorites.filter { $0.entry?.id == entry.id })
        } else {
            perform {
                let fst = try FLFavorites.add(entry)
                if let added = added { DispatchQueue.main.async { added(fst) } }
                return nil
            }
        }
    }

    func remove(_ targets: [Favorite]) {
        guard !targets.isEmpty else { return }
        perform {
            for favorite in targets { try FLFavorites.remove(favorite, backup: self.backup) }
            return .removed(targets.count)
        }
    }

    /// One click: each unsorted favourite goes into the FL category its plugin reports, or its name suggests.
    func sortByCategory() {
        let targets = unsorted
        guard !targets.isEmpty else { return }
        let entries = self.entries
        perform {
            // Plugins are loaded in helper processes, a few at a time; each favourite needs one read at most
            let bundles = Array(Set(targets.compactMap { self.taggedBundle(for: $0, in: entries) }))
            var found: [URL: [String]] = [:]
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: bundles.count) { n in
                let bundle = bundles[n]
                DispatchQueue.main.async { self.current = bundle.url.deletingPathExtension().lastPathComponent }
                let tags = self.tags.tags(bundle.format, bundle.url)
                lock.lock()
                found[bundle.url] = tags
                lock.unlock()
            }
            DispatchQueue.main.async { self.current = "" }

            var moved = 0
            for favorite in targets {
                let tags = self.taggedBundle(for: favorite, in: entries).flatMap { found[$0.url] } ?? []
                let folder = FLCategories.guess(section: favorite.section, name: favorite.entry?.name ?? favorite.title,
                                                tags: tags)
                try FLCategories.move(favorite, to: folder, journal: self.journal, pictures: .shared)
                moved += 1
            }
            return .sorted(moved)
        }
    }

    /// Moves a plugin's favourites into a folder by hand; nil puts them back at the top of the section.
    func setCategory(_ row: FavoriteRow, to folder: String?) {
        let targets = favorites(of: row)
        guard !targets.isEmpty else { return }
        perform {
            for favorite in targets {
                try FLCategories.move(favorite, to: folder, journal: self.journal, pictures: .shared)
            }
            return nil
        }
    }

    func unsort() {
        perform { .unsorted(FLCategories.restoreAll(journal: self.journal, pictures: .shared)) }
    }

    /// The VST3 or CLAP file to ask for tags: the favourite's own format, else another format of the same plugin.
    private func taggedBundle(for favorite: Favorite, in entries: [InstalledEntry]) -> TaggedBundle? {
        guard let entry = favorite.entry else { return nil }
        let siblings = [entry] + entries.filter {
            $0.section == entry.section && FLFavorites.normalize($0.vendor) == FLFavorites.normalize(entry.vendor)
                && FLFavorites.normalize($0.name) == FLFavorites.normalize(entry.name)
        }
        for format in [PluginFormat.vst3, .clap] {
            for sibling in siblings where sibling.format == format.rawValue {
                if let path = sibling.files.first(where: { $0.lowercased().hasSuffix("." + format.fileExtension) }),
                   FileManager.default.fileExists(atPath: path) {
                    return TaggedBundle(format: format, url: URL(fileURLWithPath: path))
                }
            }
        }
        return nil
    }

    func restore() {
        perform { .restored(FLFavorites.restoreAll(backup: self.backup)) }
    }

    /// Runs a change off the main thread, then reports its status and rescans.
    private func perform(_ work: @escaping () throws -> FavoritesStatus?) {
        guard !busy else { return }
        busy = true
        queue.async {
            let result = Result { try work() }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let status):  if let status = status { self.status = status }
                case .failure(let error):   self.status = .failed(error.localizedDescription)
                }
                self.scan()
            }
        }
    }

}
