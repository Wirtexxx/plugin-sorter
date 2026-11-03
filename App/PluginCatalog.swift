import Foundation

/// One plugin as the main list shows it: its files on disk together with what FL Studio knows about it.
struct CatalogRow: Identifiable {
    let id: String
    let name: String
    let vendor: String
    /// Nil when the plugin was deleted from disk but FL still has it as a favourite.
    let plugin: ManagedPlugin?
    /// FL's scans of it, every format and section.
    let entries: [InstalledEntry]
    let favorites: [Favorite]

    var isKnownToFL: Bool { !entries.isEmpty }
    var isFavorite: Bool { !favorites.isEmpty }
    var isStale: Bool { plugin == nil }
}

enum PluginCatalog {
    /// Every disk plugin as a row, with FL's entries and favourites joined in. FL's own plugins are left out;
    /// FL entries with no plugin on disk only show up when they are favourites of a deleted plugin.
    /// - Parameter removed: ids of entries whose plugin is gone (`Availability.removed`).
    static func rows(plugins: [ManagedPlugin], entries: [InstalledEntry], favorites: [Favorite],
                     removed: Set<String>) -> [CatalogRow] {
        let groups = Dictionary(grouping: entries.filter { !$0.isNative }) { key($0.vendor, $0.name) }

        // A bundle path FL loads is the surest link; vendor and name catch the AU, which FL lists without one
        var byPath: [String: ManagedPlugin] = [:]
        var byName: [String: ManagedPlugin] = [:]
        for plugin in plugins {
            for bundle in plugin.bundles { byPath[bundle.url.standardizedFileURL.path] = plugin }
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

        func favoritesOf(_ group: [InstalledEntry]) -> [Favorite] {
            let ids = Set(group.map(\.id))
            return favorites.filter { $0.entry.map { ids.contains($0.id) } ?? false }
        }

        var rows = plugins.map { plugin -> CatalogRow in
            let group = joined[plugin.key] ?? []
            return CatalogRow(id: plugin.key, name: plugin.name, vendor: plugin.vendor, plugin: plugin,
                              entries: group, favorites: favoritesOf(group))
        }
        for orphan in orphans where orphan.entries.allSatisfy({ removed.contains($0.id) }) {
            let stale = favoritesOf(orphan.entries)
            guard !stale.isEmpty, let first = orphan.entries.first else { continue }
            rows.append(CatalogRow(id: "fl|" + orphan.key, name: first.name, vendor: first.vendor, plugin: nil,
                                   entries: orphan.entries, favorites: stale))
        }
        return rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func key(_ vendor: String, _ name: String) -> String {
        FLFavorites.normalize(vendor) + "|" + FLFavorites.normalize(name)
    }

    /// The plugin's name, and without its developer in front ("FabFilter Pro-Q 4" is "Pro-Q 4" in FL).
    private static func names(of plugin: ManagedPlugin) -> [String] {
        let prefix = plugin.vendor + " "
        guard !plugin.vendor.isEmpty, plugin.name.lowercased().hasPrefix(prefix.lowercased()) else { return [plugin.name] }
        return [plugin.name, String(plugin.name.dropFirst(prefix.count))]
    }
}
