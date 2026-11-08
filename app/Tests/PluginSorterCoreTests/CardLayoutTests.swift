import Testing
import AppKit
@testable import PluginSorterCore

@Suite("Card layout")
struct CardLayoutTests {
    @Test func wideShotsFillTheArea() {
        #expect(CardLayout.mode(for: CGSize(width: 640, height: 313)) == .fill)  // Ozone 11, 2.04
        #expect(CardLayout.mode(for: CGSize(width: 180, height: 100)) == .fill)  // exactly 1.8
        #expect(CardLayout.mode(for: CGSize(width: 270, height: 100)) == .fill)  // exactly 2.7
    }

    @Test func otherShotsSitOnTheBackground() {
        #expect(CardLayout.mode(for: CGSize(width: 640, height: 398)) == .fit)   // Serum 2, 1.61
        #expect(CardLayout.mode(for: CGSize(width: 357, height: 640)) == .fit)   // portrait
        #expect(CardLayout.mode(for: CGSize(width: 1000, height: 100)) == .fit)  // 10:1
    }

    @Test func degenerateSizesDontCrash() {
        #expect(CardLayout.mode(for: .zero) == .fit)
        #expect(CardLayout.mode(for: CGSize(width: 1, height: 1)) == .fit)
    }

    @Test @MainActor func everyCardIsTheSameSize() throws {
        for size in [CGSize(width: 1, height: 1), CGSize(width: 357, height: 640), CGSize(width: 4000, height: 400)] {
            let png = try #require(FLCard.png(title: "T", vendor: "V", shot: NSImage(size: size)))
            let rep = try #require(NSBitmapImageRep(data: png))
            #expect(rep.pixelsWide == 208 && rep.pixelsHigh == 128)
        }
    }
}
