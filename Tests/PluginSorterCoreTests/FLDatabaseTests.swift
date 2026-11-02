import Foundation
import Testing
@testable import PluginSorterCore

@Suite("FL Studio .fst presets")
struct FSTTests {
    private func read(_ data: Data) throws -> FSTInfo? {
        let dir = try TempDir()
        let url = dir.path("preset.fst")
        try data.write(to: url)
        return FST.read(url)
    }

    @Test func readsPluginRecords() throws {
        let info = try #require(try read(FSTBuilder.make(display: "Pro-Q 4", name: "Pro-Q 4", vendor: "FabFilter",
                                                         path: "/Library/Audio/Plug-Ins/CLAP/FabFilter Pro-Q 4.clap")))
        #expect(info.name == "Pro-Q 4")
        #expect(info.vendor == "FabFilter")
        #expect(info.path == "/Library/Audio/Plug-Ins/CLAP/FabFilter Pro-Q 4.clap")
    }

    @Test func pluginNameWinsOverDisplayName() throws {
        let info = try #require(try read(FSTBuilder.make(display: "My Renamed EQ", name: "Pro-Q 4", vendor: "FabFilter")))
        #expect(info.name == "Pro-Q 4")
    }

    @Test func fallsBackToDisplayName() throws {
        let info = try #require(try read(FSTBuilder.make(display: "Audio Clip")))
        #expect(info.name == "Audio Clip")
        #expect(info.vendor.isEmpty)
    }

    @Test func handlesMultiByteLengths() throws {
        // A path over 127 bytes needs a two-byte length for the event and a long record
        let long = "/Library/Audio/Plug-Ins/VST3/" + String(repeating: "Very Long Folder/", count: 12) + "Plugin.vst3"
        let info = try #require(try read(FSTBuilder.make(name: "Plugin", vendor: "Vendor", path: long)))
        #expect(info.path == long)
        #expect(info.vendor == "Vendor")
    }

    @Test func rejectsOtherFiles() throws {
        #expect(try read(Data("not a preset at all".utf8)) == nil)
        #expect(try read(Data("FLhd".utf8) + FSTBuilder.le32(6) + Data(count: 20)) == nil)
    }

    @Test func survivesTruncatedFiles() throws {
        let full = FSTBuilder.make(display: "OTT", name: "OTT", vendor: "Xfer Records")
        for length in stride(from: 23, to: full.count, by: 7) {
            _ = try read(full.prefix(length))  // must not crash
        }
    }
}

@Suite("FL Studio pictures")
struct FLPictureTests {
    let dir: TempDir
    let manifest: PictureManifest
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])

    init() throws {
        dir = try TempDir()
        manifest = PictureManifest(url: dir.path("manifest.json"))
        try FileManager.default.createDirectory(at: dir.path("Effects/Dynamics"), withIntermediateDirectories: true)
    }

    private func plugin(_ name: String, in folder: String = "Effects") throws -> FLPlugin {
        let fst = dir.path("\(folder)/\(name).fst")
        try FSTBuilder.make(name: name, vendor: "Vendor").write(to: fst)
        return FLPlugin(fst: fst, title: name, info: try #require(FST.read(fst)), hasPicture: false, source: nil)
    }

    @Test func installWritesPictureAndNfo() throws {
        let ott = try plugin("OTT")
        try FLDatabase.install(png, for: ott, source: .screenshot, manifest: manifest)
        #expect(try Data(contentsOf: ott.picture) == png)
        #expect(try String(contentsOf: ott.nfo, encoding: .utf8) == "Bitmap=OTT.png")
    }

    @Test func removeDeletesWhatItCreated() throws {
        let ott = try plugin("OTT")
        try FLDatabase.install(png, for: ott, source: .card, manifest: manifest)
        FLDatabase.remove(ott, manifest: manifest)
        #expect(!FileManager.default.fileExists(atPath: ott.picture.path))
        #expect(!FileManager.default.fileExists(atPath: ott.nfo.path))
        #expect(manifest.records.isEmpty)
    }

    @Test func existingNfoKeepsItsLinesAndIsRestoredByteForByte() throws {
        let proQ = try plugin("Pro-Q 4")
        // Compare bytes: Foundation versions differ in whether String I/O keeps a UTF-8 BOM
        let before = Data([0xEF, 0xBB, 0xBF]) + Data("fileversion=2\r\ncolor=$40B6F6\r\nBitmap=old.png".utf8)
        try before.write(to: proQ.nfo)

        try FLDatabase.install(png, for: proQ, source: .screenshot, manifest: manifest)
        try FLDatabase.install(png, for: proQ, source: .custom, manifest: manifest)  // a second write must not lose the original
        let expected = Data([0xEF, 0xBB, 0xBF]) + Data("fileversion=2\r\ncolor=$40B6F6\r\nBitmap=Pro-Q 4.png".utf8)
        #expect(try Data(contentsOf: proQ.nfo) == expected)

        FLDatabase.remove(proQ, manifest: PictureManifest(url: dir.path("manifest.json")))  // also survives a reload
        #expect(try Data(contentsOf: proQ.nfo) == before)
    }

    @Test func bomInFrontOfTheBitmapLineIsKept() throws {
        let ott = try plugin("OTT")
        try (Data([0xEF, 0xBB, 0xBF]) + Data("Bitmap=old.png".utf8)).write(to: ott.nfo)
        try FLDatabase.install(png, for: ott, source: .card, manifest: manifest)
        #expect(try Data(contentsOf: ott.nfo) == Data([0xEF, 0xBB, 0xBF]) + Data("Bitmap=OTT.png".utf8))
    }

    @Test func manifestSurvivesReload() throws {
        let ott = try plugin("OTT")
        try FLDatabase.install(png, for: ott, source: .custom, manifest: manifest)
        let reloaded = PictureManifest(url: dir.path("manifest.json"))
        #expect(reloaded[ott.picture]?.source == .custom)
    }

    @Test func scanFindsFavouritesAndSkipsFLModules() throws {
        let ott = try plugin("OTT")
        _ = try plugin("Fruity Limiter", in: "Effects/Dynamics")
        try FSTBuilder.make(display: "Audio Clip").write(to: dir.path("Effects/Audio Clip.fst"))
        try FLDatabase.install(png, for: ott, source: .screenshot, manifest: manifest)

        let found = FLDatabase.scan(manifest, root: dir.url)
        #expect(found.map(\.title) == ["Fruity Limiter", "OTT"])
        #expect(found.first { $0.title == "OTT" }?.source == .screenshot)
        #expect(found.first { $0.title == "Fruity Limiter" }?.hasPicture == false)
    }
}
