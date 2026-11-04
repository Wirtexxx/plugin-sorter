import Foundation
import Testing
@testable import PluginSorterCore

@Suite("A click on the star")
struct StarTapTests {
    private let entry = InstalledEntry(fst: URL(fileURLWithPath: "/fl/OTT.fst"), section: "Effects", format: "VST3",
                                       name: "OTT", vendor: "Xfer Records", files: [])

    private func row(known: Bool) -> CatalogRow {
        CatalogRow(id: "row", name: "OTT", vendor: "Xfer Records", plugin: nil,
                   entries: known ? [entry] : [], favorites: [], isStale: false)
    }

    @Test func aPluginFLKnowsIsToggled() {
        #expect(StarTap(row: row(known: true), busy: false) == .toggle)
    }

    @Test func aPluginFLHasNotScannedIsExplained() {
        #expect(StarTap(row: row(known: false), busy: false) == .notSeen)
    }

    @Test func aRunningChangeIsWaitedFor() {
        #expect(StarTap(row: row(known: true), busy: true) == .wait)
    }

    @Test func theExplanationDoesNotWaitForAChange() {
        #expect(StarTap(row: row(known: false), busy: true) == .notSeen)
    }
}
