import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Tabs of a plugin's details")
struct DetailsTabTests {
    private let plugin = ManagedPlugin(key: "ott|xfer", name: "OTT", vendor: "Xfer Records", bundles: [])
    private let entry = InstalledEntry(fst: URL(fileURLWithPath: "/fl/OTT.fst"), section: "Effects", format: "VST3",
                                       name: "OTT", vendor: "Xfer Records", files: [])

    private func row(plugin: ManagedPlugin?, known: Bool, stale: Bool = false) -> CatalogRow {
        CatalogRow(id: "row", name: "OTT", vendor: "Xfer Records", plugin: plugin,
                   entries: known ? [entry] : [], favorites: [], isStale: stale)
    }

    @Test func installedPluginKnownToFLHasAllTabs() {
        #expect(DetailsTab.available(for: row(plugin: plugin, known: true)) == [.files, .fl, .tags, .license])
    }

    @Test func pluginUnknownToFLHasNoFLTab() {
        #expect(DetailsTab.available(for: row(plugin: plugin, known: false)) == [.files, .tags, .license])
    }

    @Test func pluginOutsideTheFolderHasOnlyFL() {
        #expect(DetailsTab.available(for: row(plugin: nil, known: true)) == [.fl])
    }

    @Test func stalePluginHasNoTabs() {
        #expect(DetailsTab.available(for: row(plugin: nil, known: true, stale: true)).isEmpty)
    }

    @Test func missingTabFallsBackToFiles() {
        #expect(DetailsTab.resolved(.fl, for: row(plugin: plugin, known: false)) == .files)
    }

    @Test func availableTabStaysSelected() {
        #expect(DetailsTab.resolved(.license, for: row(plugin: plugin, known: true)) == .license)
    }

    @Test func onlyTabIsChosenWhenFilesIsMissing() {
        #expect(DetailsTab.resolved(.tags, for: row(plugin: nil, known: true)) == .fl)
    }

    @Test func noTabsResolveToNil() {
        #expect(DetailsTab.resolved(.files, for: row(plugin: nil, known: true, stale: true)) == nil)
    }
}
