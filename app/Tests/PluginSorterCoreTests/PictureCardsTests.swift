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
