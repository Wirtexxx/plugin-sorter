import Foundation

/// One plugin as the main list shows it: its files on disk together with what FL Studio knows about it.
struct CatalogRow: Identifiable {
    let id: String
    let name: String
    let vendor: String
    /// Nil when it isn't in /Library/Audio/Plug-Ins: deleted, or installed somewhere FL also looks.
    let plugin: ManagedPlugin?
    /// FL's scans of it, every format and section.
    let entries: [InstalledEntry]
    let favorites: [Favorite]

    var isKnownToFL: Bool { !entries.isEmpty }
    var isFavorite: Bool { !favorites.isEmpty }
    /// Deleted from disk but still an FL favourite.
    let isStale: Bool
}

/// What a click on the star does. The star never turns its click down: a disabled button would pass it
/// on to the row, which opens instead.
enum StarTap: Equatable {
    case toggle
    /// FL has no scan of the plugin, and a favourite is a copy of that scan.
    case notSeen
    /// A change to the favourites is still running.
    case wait

    init(row: CatalogRow, busy: Bool) {
        self = !row.isKnownToFL ? .notSeen : busy ? .wait : .toggle
    }
}

enum PluginCatalog {
    /// Every disk plugin as a row, with FL's entries and favourites joined in. FL's own plugins are left out.
    /// FL entries with no plugin here still get a row: installed elsewhere, or favourites of a deleted plugin.
    /// - Parameter removed: ids of entries whose plugin is gone (`Availability.removed`).
    static func rows(plugins: [ManagedPlugin], entries: [InstalledEntry], favorites: [Favorite],
                     removed: Set<String>) -> [CatalogRow] {
        let groups = Dictionary(grouping: entries.filter { !$0.isNative }) { key($0.vendor, $0.name) }

        // A bundle path FL loads is the surest link; vendor and name catch the AU, which FL lists without one
        var byPath: [String: ManagedPlugin] = [:]
        var byName: [String: ManagedPlugin] = [:]
        for plugin in plugins {
            // A turned-off plugin is still found where FL last saw it
            for bundle in plugin.bundles {
                byPath[bundle.url.standardizedFileURL.path] = plugin
                byPath[bundle.enabledURL.standardizedFileURL.path] = plugin
            }
            for name in names(of: plugin) { byName[key(plugin.vendor, name)] = byName[key(plugin.vendor, name)] ?? plugin }
        }

        var joined: [String: [InstalledEntry]] = [:]
        var orphans: [(key: String, entries: [InstalledEntry])] = []
        for (groupKey, group) in groups {
            let paths = group.flatMap(\.files).map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            if let plugin = paths.lazy.compactMap({ byPath[$0] }).first ?? byName[groupKey] {
                joined[plugin.key, default: []] += group
            } else {
                orphans.append((groupKey, group))
            }
        }

        // Looked up rather than searched for each row: this runs while the window draws
        var favoriteIndexes: [String: [Int]] = [:]
        for (index, favorite) in favorites.enumerated() {
            if let entry = favorite.entry { favoriteIndexes[entry.id, default: []].append(index) }
        }

        func favoritesOf(_ group: [InstalledEntry]) -> [Favorite] {
            Set(group.map(\.id)).flatMap { favoriteIndexes[$0] ?? [] }.sorted().map { favorites[$0] }
        }

        var rows = plugins.map { plugin -> CatalogRow in
            let group = joined[plugin.key] ?? []
            return CatalogRow(id: plugin.key, name: plugin.name, vendor: plugin.vendor, plugin: plugin,
                              entries: group, favorites: favoritesOf(group), isStale: false)
        }
        for orphan in orphans {
            let gone = orphan.entries.allSatisfy { removed.contains($0.id) }
            let favored = favoritesOf(orphan.entries)
            // A deleted plugin is only worth a row while it still clutters FL's favourites
            guard !gone || !favored.isEmpty, let first = orphan.entries.first else { continue }
            rows.append(CatalogRow(id: "fl|" + orphan.key, name: first.name, vendor: first.vendor, plugin: nil,
                                   entries: orphan.entries, favorites: favored, isStale: gone))
        }
        return rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func key(_ vendor: String, _ name: String) -> String {
        FLFavorites.normalize(vendor) + "|" + FLFavorites.normalize(name)
    }

    /// The plugin's name, and without its developer in front ("FabFilter Pro-Q 4" is "Pro-Q 4" in FL).
    /// An Audio Unit's own name counts too: FL lists it by that, and its file may be called anything.
    private static func names(of plugin: ManagedPlugin) -> [String] {
        var names = [plugin.name]
        let prefix = plugin.vendor + " "
        if !plugin.vendor.isEmpty, plugin.name.lowercased().hasPrefix(prefix.lowercased()) {
            names.append(String(plugin.name.dropFirst(prefix.count)))
        }
        for bundle in plugin.bundles where !bundle.auName.isEmpty && !names.contains(bundle.auName) {
            names.append(bundle.auName)
        }
        return names
    }
}
