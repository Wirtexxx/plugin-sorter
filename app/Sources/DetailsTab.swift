import Foundation

/// The parts of a plugin's details, one on screen at a time.
enum DetailsTab: String, CaseIterable, Identifiable {
    case files, fl, tags, license

    var id: String { rawValue }

    /// The tabs this row has something to show on. A plugin gone from disk has none: its problem says it all.
    static func available(for row: CatalogRow) -> [DetailsTab] {
        if row.isStale { return [] }
        guard row.plugin != nil else { return [.fl] }
        return allCases.filter { $0 != .fl || row.isKnownToFL }
    }

    /// The tab to open: the one asked for if this row has it, else the row's first.
    static func resolved(_ wanted: DetailsTab, for row: CatalogRow) -> DetailsTab? {
        let tabs = available(for: row)
        return tabs.contains(wanted) ? wanted : tabs.first
    }
}
