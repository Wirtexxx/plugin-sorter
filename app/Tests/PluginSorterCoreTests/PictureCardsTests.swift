import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Cards of ours waiting for a real picture")
struct PictureCardsTests {
    private let dir: TempDir
    init() throws { dir = try TempDir() }

    private func favorite(_ name: String, hasPicture: Bool = true, source: FLPlugin.Source?) -> FLPlugin {
        FLPlugin(fst: URL(fileURLWithPath: "/db/Effects/\(name).fst"), title: name,
                 info: FSTInfo(name: name, vendor: "Waves", path: ""), hasPicture: hasPicture, source: source)
    }

    @Test func onlyACardWeDrewIsAPlaceholder() {
        #expect(favorite("A", source: .card).isPlaceholder)
        #expect(!favorite("A", source: .screenshot).isPlaceholder)
        #expect(!favorite("A", source: .custom).isPlaceholder)
        #expect(!favorite("A", source: nil).isPlaceholder)
        #expect(!favorite("A", hasPicture: false, source: nil).isPlaceholder)
    }

    @Test func addKeepsEveryMissingPictureButOnlyCardsWithARealOne() {
        let missing = favorite("Missing", hasPicture: false, source: nil)
        let found = favorite("Found", source: .card)
        let notFound = favorite("NotFound", source: .card)
        let shot = URL(fileURLWithPath: "/p/found.png")
        let targets = PictureTargets.add(missing: [missing], cards: [found, notFound], shots: [found.id: shot])
        #expect(targets.map(\.id) == [missing.id, found.id])
    }

    private func row(_ name: String, vendor: String, plugin: ManagedPlugin? = nil) -> CatalogRow {
        CatalogRow(id: name, name: name, vendor: vendor, plugin: plugin, entries: [], favorites: [], isStale: false)
    }

    @Test func aWavesPluginWithoutAFavouriteIsLookedUpByItsName() {
        #expect(row("C4 Mono", vendor: "Waves").pictureKeys == ["waves|c4mono"])
    }

    @Test func aPluginOnDiskIsLookedUpByItsOwnKeys() {
        let plugin = ManagedPlugin(key: "ott|xfer", name: "OTT", vendor: "Xfer", bundles: [])
        #expect(row("OTT", vendor: "Xfer", plugin: plugin).pictureKeys == ["ott|xfer"])
    }

    @Test func anotherPluginOnlyFLKnowsHasNothingToLookUp() {
        #expect(row("Gone", vendor: "Xfer").pictureKeys.isEmpty)
    }

    @Test func theDatabaseIsAskedForEveryRowWithoutAPicture() {
        let plugin = ManagedPlugin(key: "ott|xfer", name: "OTT", vendor: "Xfer", bundles: [])
        let rows = [row("C4 Mono", vendor: "Waves"), row("OTT", vendor: "Xfer", plugin: plugin),
                    row("CLA-76 Stereo", vendor: "Waves"), row("Gone", vendor: "Xfer")]
        let wanted = PictureTargets.database(rows) { $0.name == "CLA-76 Stereo" }
        #expect(wanted == ["waves|c4mono": ["waves|c4mono"], "ott|xfer": ["ott|xfer"]])
    }

    @Test func theAppShowsItsFullPictureOverFLsSmallOne() {
        let shot = URL(fileURLWithPath: "/p/full.png")
        for source: FLPlugin.Source? in [.screenshot, .card, nil] {
            let fl = favorite("A", source: source)
            #expect(PictureChoice.artwork(fl: fl, shot: shot)?.url == shot)
        }
    }

    @Test func aPictureTheUserChoseWins() {
        let fl = favorite("A", source: .custom)
        #expect(PictureChoice.artwork(fl: fl, shot: URL(fileURLWithPath: "/p/full.png"))?.url == fl.picture)
    }

    @Test func withoutAFullPictureFLsIsShown() {
        let fl = favorite("A", source: .screenshot)
        #expect(PictureChoice.artwork(fl: fl, shot: nil)?.url == fl.picture)
        #expect(PictureChoice.artwork(fl: favorite("B", hasPicture: false, source: nil), shot: nil) == nil)
    }

    @Test @MainActor func aCheckedCardIsNoLongerWaitingAndStaysChecked() {
        let local = LocalPictures(directory: dir.path("p"))
        let library = FLLibrary(demo: true, local: local)
        let checked = favorite("Checked", source: .card)
        let waiting = favorite("Waiting", source: .card)
        library.plugins = [checked, waiting, favorite("Shot", source: .screenshot)]

        #expect(library.uncheckedCards.map(\.id) == [checked.id, waiting.id])
        library.markChecked([checked])
        #expect(library.uncheckedCards.map(\.id) == [waiting.id])

        let reopened = FLLibrary(demo: true, local: LocalPictures(directory: dir.path("p")))
        reopened.plugins = library.plugins
        #expect(reopened.uncheckedCards.map(\.id) == [waiting.id])
    }
}
