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
    case failed(String)
}

/// State of the Favourites section: what FL scanned, what's in its browser, and what's gone.
final class FavoritesLibrary: ObservableObject {
    @Published private(set) var entries: [InstalledEntry] = []
    @Published private(set) var favorites: [Favorite] = []
    @Published private(set) var availability: [String: Availability] = [:]
    @Published var query = ""
    @Published var onlyFavorites = false
    @Published var showStock = false
    @Published var busy = false
    @Published var status: FavoritesStatus = .idle

    private let backup = FavoriteBackup()
    private let queue = DispatchQueue(label: "plugin-sorter.favorites", qos: .userInitiated)
    /// Formats in the order a star picks them when a plugin isn't a favourite yet.
    private static let preference = ["VST3", "CLAP", "AudioUnit", "VST"]

    var canRestore: Bool { !backup.records.isEmpty }

    var rows: [FavoriteRow] {
        let grouped = Dictionary(grouping: entries) {
            $0.section + "|" + FLFavorites.normalize($0.vendor) + "|" + FLFavorites.normalize($0.name)
        }
        return grouped.map { key, items in
            let sorted = items.sorted { rank($0.format) < rank($1.format) }
            return FavoriteRow(key: key, name: sorted[0].name, vendor: sorted[0].vendor,
                               section: sorted[0].section, entries: sorted)
        }
        .filter { row in
            (showStock || !row.isNative)
                && (!onlyFavorites || row.entries.contains(where: isFavorite))
                && (query.isEmpty || row.name.localizedCaseInsensitiveContains(query)
                    || row.vendor.localizedCaseInsensitiveContains(query))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Favourites whose plugin was deleted: they only clutter FL's browser.
    var stale: [Favorite] {
        favorites.filter { $0.entry.map { availability[$0.id] == .removed } ?? false }
    }

    func isFavorite(_ entry: InstalledEntry) -> Bool { favorites.contains { $0.entry?.id == entry.id } }

    func availability(of row: FavoriteRow) -> Availability {
        let states = row.entries.map { availability[$0.id] ?? .unknown }
        if states.contains(.available) { return .available }
        if states.contains(.moved) { return .moved }
        return states.allSatisfy { $0 == .removed } ? .removed : .unknown
    }

    func scan() {
        queue.async {
            let entries = FLFavorites.installed()
            let favorites = FLFavorites.favorites(installed: entries)
            let bundleNames = Set(PluginInventory.scan().flatMap(\.bundles).map { $0.url.lastPathComponent })
            let audioUnits = Set(AVAudioUnitComponentManager.shared().components { _, _ in true }
                .map { FLFavorites.auKey(vendor: $0.manufacturerName, name: $0.name) })
            var availability: [String: Availability] = [:]
            for entry in entries {
                availability[entry.id] = FLFavorites.availability(entry, bundleNames: bundleNames, audioUnits: audioUnits)
            }
            DispatchQueue.main.async {
                self.entries = entries
                self.favorites = favorites
                self.availability = availability
            }
        }
    }

    /// A star on the whole plugin: removes all its favourites, or adds the preferred format.
    func toggle(_ row: FavoriteRow) {
        if row.entries.contains(where: isFavorite) {
            remove(favorites.filter { fav in row.entries.contains { $0.id == fav.entry?.id } })
        } else if let entry = row.entries.first(where: { availability[$0.id] != .removed }) ?? row.entries.first {
            toggle(entry)
        }
    }

    /// A format chip: adds or removes just that format.
    func toggle(_ entry: InstalledEntry) {
        if isFavorite(entry) {
            remove(favorites.filter { $0.entry?.id == entry.id })
        } else {
            perform {
                _ = try FLFavorites.add(entry)
                return nil
            }
        }
    }

    func removeStale() { remove(stale) }

    func remove(_ targets: [Favorite]) {
        guard !targets.isEmpty else { return }
        perform {
            for favorite in targets { try FLFavorites.remove(favorite, backup: self.backup) }
            return .removed(targets.count)
        }
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

    private func rank(_ format: String) -> Int { Self.preference.firstIndex(of: format) ?? Self.preference.count }
}
