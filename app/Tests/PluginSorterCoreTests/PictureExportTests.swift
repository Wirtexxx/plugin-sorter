import AppKit
import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Export for the picture database")
struct PictureExportTests {
    private let dir: TempDir
    private var repo: URL { dir.path("repo") }
    init() throws { dir = try TempDir() }

    private static func png(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func index() throws -> PictureIndex {
        try #require(PictureIndex.parse(Data(contentsOf: repo.appendingPathComponent("index.json"))))
    }

    @Test func exportedPicturesAreFoundByEveryKey() throws {
        let count = try PictureExport.export([(keys: ["a|v", "a2|v"], png: Self.png(width: 20, height: 10)),
                                              (keys: ["b|v"], png: Self.png(width: 8, height: 8))], into: repo)
        #expect(count == 2)
        let index = try index()
        #expect(index.entry(for: ["a|v"])?.key == "a|v")
        #expect(index.entry(for: ["a2|v"])?.key == "a|v")
        #expect(index.entry(for: ["b|v"])?.entry.width == 8)
        #expect(index.pictures["a|v"]?.width == 20 && index.pictures["a|v"]?.height == 10)
    }

    @Test func fileNamesAreTheOnesTheAppUses() throws {
        _ = try PictureExport.export([(keys: ["serum2|xfer"], png: Self.png(width: 4, height: 4))], into: repo)
        let expected = LocalPictures(directory: dir.path("x")).url(for: "serum2|xfer").lastPathComponent
        #expect(try index().pictures["serum2|xfer"]?.file == "pictures/" + expected)
        #expect(FileManager.default.fileExists(atPath: repo.appendingPathComponent("pictures/" + expected).path))
    }

    @Test func aSecondExportKeepsWhatWasThere() throws {
        _ = try PictureExport.export([(keys: ["a|v"], png: Self.png(width: 4, height: 4))], into: repo)
        _ = try PictureExport.export([(keys: ["b|v"], png: Self.png(width: 4, height: 4))], into: repo)
        #expect(Set(try index().pictures.keys) == ["a|v", "b|v"])
    }

    @Test func theHashIsTheFilesHash() throws {
        let data = Self.png(width: 4, height: 4)
        _ = try PictureExport.export([(keys: ["a|v"], png: data)], into: repo)
        let entry = try #require(try index().pictures["a|v"])
        let written = try Data(contentsOf: repo.appendingPathComponent(entry.file))
        #expect(entry.sha256 == FLLibrary.sha256(written))
        #expect(written == data)
    }

    @Test func notAPictureIsLeftOut() throws {
        #expect(try PictureExport.export([(keys: ["a|v"], png: Data("x".utf8))], into: repo) == 0)
    }

    @Test func theCaptureSizeComesFromTheOptionalArgument() {
        #expect(CaptureHelper.box(["--capture", "1", "2", "3", "/o.png"]) == Thumbnail.captureSize)
        #expect(CaptureHelper.box(["--capture", "1", "2", "3", "/o.png", "2000"]) == CGSize(width: 2000, height: 2000))
        #expect(CaptureHelper.box(["--capture", "1", "2", "3", "/o.png", "junk"]) == Thumbnail.captureSize)
    }
}
