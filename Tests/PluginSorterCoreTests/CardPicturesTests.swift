import Testing
import AppKit
import Foundation
@testable import PluginSorterCore

struct CardPicturesTests {
    private let dir: TempDir

    init() throws { dir = try TempDir() }

    /// Writes a PNG of the given pixel width, dated so the test decides whether it "changed".
    private func writePicture(_ name: String, width: Int, modified: Date) throws -> URL {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 4, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let url = dir.path(name)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    @Test func aPictureOnDiskIsRead() throws {
        let url = try writePicture("a.png", width: 8, modified: Date())
        #expect(CardPictures().image(at: url) != nil)
    }

    @Test func aMissingPictureGivesNothing() {
        #expect(CardPictures().image(at: dir.path("gone.png")) == nil)
    }

    @Test func anUnchangedPictureIsNotReadAgain() throws {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let url = try writePicture("a.png", width: 8, modified: date)
        let pictures = CardPictures()
        let first = try #require(pictures.image(at: url))
        #expect(pictures.image(at: url) === first)
    }

    @Test func aRetakenPictureReplacesTheOldOne() throws {
        let url = try writePicture("a.png", width: 8, modified: Date(timeIntervalSince1970: 1_000_000))
        let pictures = CardPictures()
        _ = pictures.image(at: url)
        _ = try writePicture("a.png", width: 32, modified: Date(timeIntervalSince1970: 2_000_000))
        #expect(pictures.image(at: url)?.representations.first?.pixelsWide == 32)
    }

    @Test func aRemovedPictureIsForgotten() throws {
        let url = try writePicture("a.png", width: 8, modified: Date())
        let pictures = CardPictures()
        _ = pictures.image(at: url)
        try FileManager.default.removeItem(at: url)
        #expect(pictures.image(at: url) == nil)
    }
}

extension CardPicturesTests {
    @Test func aPictureNotReadYetIsNotInMemory() throws {
        let url = try writePicture("a.png", width: 8, modified: Date())
        #expect(CardPictures().cached(at: url) == nil)
    }

    @Test func aPictureReadOnceIsInMemory() throws {
        let url = try writePicture("a.png", width: 8, modified: Date())
        let pictures = CardPictures()
        let image = try #require(pictures.image(at: url))
        #expect(pictures.cached(at: url) === image)
    }
}
