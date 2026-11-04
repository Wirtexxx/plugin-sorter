import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Files the app keeps")
struct JSONStoreTests {
    let dir: TempDir
    init() throws { dir = try TempDir() }

    private func corrupt(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
    }

    @Test func whatIsSavedComesBack() throws {
        let store = JSONStore<[String: Int]>(url: dir.path("a/b.json"))
        #expect(store.load() == nil)
        try store.save(["x": 1])
        #expect(store.load() == ["x": 1])
    }

    @Test func anUnreadableFileIsKeptAside() throws {
        let url = dir.path("b.json")
        try corrupt(url)
        let store = JSONStore<[String: Int]>(url: url)
        #expect(store.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: url.appendingPathExtension("bad")) == Data("not json".utf8))
    }

    @Test func aFailedSaveIsAnError() throws {
        try Data().write(to: dir.path("file"))
        let store = JSONStore<[String: Int]>(url: dir.path("file/b.json"))
        #expect(throws: (any Error).self) { try store.save(["x": 1]) }
    }

    @Test func aDamagedManifestIsNotOverwritten() throws {
        let url = dir.path("manifest.json")
        try corrupt(url)
        let manifest = PictureManifest(url: url)
        try manifest.set(PictureManifest.Record(source: .card, originalNfoData: nil, originalNfo: nil), for: dir.path("a.png"))
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("bad").path))
    }

    @Test func aDamagedCategoryJournalIsNotOverwritten() throws {
        let url = dir.path("journal.json")
        try corrupt(url)
        try CategoryJournal(url: url).record(from: dir.path("a"), to: dir.path("b"))
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("bad").path))
    }

    @Test func aDamagedBackupListIsNotOverwritten() throws {
        let folder = dir.path("backup")
        try corrupt(folder.appendingPathComponent("removed.json"))
        try FavoriteBackup(directory: folder).add(.init(original: "/a", backup: "/b", date: Date()))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("removed.json.bad").path))
    }

    /// FL's .nfo is only touched once the way back is on disk.
    @Test func noPictureGoesInWithoutItsRecord() throws {
        try Data().write(to: dir.path("file"))
        let fst = dir.path("OTT.fst")
        try Data().write(to: fst)
        try Data("Bitmap=old.png".utf8).write(to: dir.path("OTT.nfo"))
        let plugin = FLPlugin(fst: fst, title: "OTT", info: FSTInfo(), hasPicture: false, source: nil)
        let manifest = PictureManifest(url: dir.path("file/manifest.json"))
        #expect(throws: (any Error).self) { try FLDatabase.install(Data([1]), for: plugin, source: .card, manifest: manifest) }
        #expect(try String(contentsOf: dir.path("OTT.nfo"), encoding: .utf8) == "Bitmap=old.png")
        #expect(!dir.exists("OTT.png"))
    }

    @Test func aFavoriteMovesWhollyOrNotAtAll() throws {
        let db = dir.path("db")
        let effects = db.appendingPathComponent("Effects")
        let target = effects.appendingPathComponent("Dynamics")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let fst = effects.appendingPathComponent("OTT.fst")
        for name in ["OTT.fst", "OTT.png", "OTT.nfo"] { try Data().write(to: effects.appendingPathComponent(name)) }
        try Data("taken".utf8).write(to: target.appendingPathComponent("OTT.nfo"))   // a leftover without its .fst
        let favorite = Favorite(fst: fst, title: "OTT", section: "Effects", entry: nil)
        let journal = CategoryJournal(url: dir.path("journal.json"))
        #expect(throws: (any Error).self) {
            try FLCategories.move(favorite, to: "Dynamics", root: db, journal: journal, pictures: PictureManifest(url: dir.path("m.json")))
        }
        for name in ["OTT.fst", "OTT.png", "OTT.nfo"] {
            #expect(FileManager.default.fileExists(atPath: effects.appendingPathComponent(name).path))
        }
        #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("OTT.fst").path))
        #expect(journal.moves.isEmpty)
    }

    @Test func removingAPictureThatCantBeUndoneStops() throws {
        let fst = dir.path("OTT.fst")
        try Data().write(to: fst)
        try Data().write(to: dir.path("OTT.png"))
        let manifest = PictureManifest(url: dir.path("manifest.json"))
        try manifest.set(.init(source: .card, originalNfoData: Data("a".utf8), originalNfo: nil), for: dir.path("OTT.png"))
        try FileManager.default.createDirectory(at: dir.path("OTT.nfo"), withIntermediateDirectories: true)  // can't be written over
        let plugin = FLPlugin(fst: fst, title: "OTT", info: FSTInfo(), hasPicture: true, source: .card)
        #expect(throws: (any Error).self) { try FLDatabase.remove(plugin, manifest: manifest) }
        #expect(manifest[dir.path("OTT.png")] != nil)
    }

    @Test func aKeepListThatCantBeWrittenIsAnError() throws {
        try Data().write(to: dir.path("file"))
        #expect(throws: (any Error).self) { try PluginFixes.keep("A.vst3", file: dir.path("file/keep.txt")) }
    }
}
