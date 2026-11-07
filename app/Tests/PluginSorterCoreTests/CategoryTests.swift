import Foundation
import Testing
@testable import PluginSorterCore

@Suite("FL Studio categories")
struct CategoryTests {
    @Test func pluginTagsComeFirst() {
        #expect(FLCategories.guess(section: "Effects", name: "Pro-Q 4", tags: ["Fx", "EQ"]) == "Filter")
        #expect(FLCategories.guess(section: "Effects", name: "CamelCrusher",
                                   tags: ["fx", "distortion", "dynamics", "filter"]) == "Distortion")
        #expect(FLCategories.guess(section: "Effects", name: "Pro-C 3",
                                   tags: ["audio-effect", "compressor"]) == "Dynamics")
        #expect(FLCategories.guess(section: "Effects", name: "trueBalance",
                                   tags: ["fx", "analyzer", "mastering"]) == "Visual")
        #expect(FLCategories.guess(section: "Effects", name: "Auto-Tune Pro", tags: ["fx", "pitch shift"]) == "Misc")
    }

    @Test func broadTagsLetTheNameDecide() {
        #expect(FLCategories.guess(section: "Effects", name: "kHs Delay", tags: ["fx", "spatial"]) == "Delay reverb")
        #expect(FLCategories.guess(section: "Effects", name: "kHs Gate", tags: ["fx", "tools"]) == "Dynamics")
        #expect(FLCategories.guess(section: "Effects", name: "kHs Haas", tags: ["fx", "spatial"]) == "Gain")
        #expect(FLCategories.guess(section: "Effects", name: "Something", tags: ["fx", "tools"]) == "Gain")
    }

    @Test func untaggedPluginsGoByName() {
        #expect(FLCategories.guess(section: "Effects", name: "ValhallaSupermassive", tags: ["fx"]) == "Delay reverb")
        #expect(FLCategories.guess(section: "Effects", name: "kHs Tape Stop", tags: ["fx"]) == "Misc")
        #expect(FLCategories.guess(section: "Effects", name: "Thermal", tags: []) == "Distortion")
        #expect(FLCategories.guess(section: "Effects", name: "OTT", tags: []) == "Dynamics")
        // Short words only match whole: "eq" is not in "frequency"
        #expect(FLCategories.guess(section: "Effects", name: "Frequency Thing", tags: []) == "Effect")
        #expect(FLCategories.guess(section: "Effects", name: "Portal", tags: ["fx"]) == "Effect")
        // A channel suffix isn't a category
        #expect(FLCategories.guess(section: "Effects", name: "CLA-76 Stereo", tags: []) == "Dynamics")
        #expect(FLCategories.guess(section: "Effects", name: "kHs Resonator", tags: ["fx", "spatial"]) == "Filter")
    }

    @Test func instruments() {
        #expect(FLCategories.guess(section: "Generators", name: "Serato Sample", tags: ["instrument", "synth"]) == "Sampler")
        #expect(FLCategories.guess(section: "Generators", name: "Diva", tags: ["instrument", "synthesizer"]) == "Synth classic")
        #expect(FLCategories.guess(section: "Generators", name: "Kick 3", tags: []) == "Drum")
        #expect(FLCategories.guess(section: "Generators", name: "Anything", tags: ["instrument", "drum"]) == "Drum")
    }

    // MARK: - Moving

    let dir: TempDir
    var db: URL { dir.path("Plugin database") }
    let pictures: PictureManifest
    let journal: CategoryJournal

    init() throws {
        dir = try TempDir()
        pictures = PictureManifest(url: dir.path("pictures.json"))
        journal = CategoryJournal(url: dir.path("categories.json"))
        try FileManager.default.createDirectory(at: db.appendingPathComponent("Effects/Dynamics"),
                                                withIntermediateDirectories: true)
    }

    private func favorite(_ path: String, picture: Bool = false) throws -> Favorite {
        let fst = db.appendingPathComponent("\(path).fst")
        try FileManager.default.createDirectory(at: fst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FSTBuilder.make(name: fst.deletingPathExtension().lastPathComponent, vendor: "Vendor").write(to: fst)
        if picture {
            let plugin = FLPlugin(fst: fst, title: "", info: FSTInfo(), hasPicture: false, source: nil)
            try FLDatabase.install(Data([1, 2, 3]), for: plugin, source: .card, manifest: pictures)
        }
        return Favorite(fst: fst, title: fst.deletingPathExtension().lastPathComponent,
                        section: String(path.split(separator: "/")[0]), entry: nil)
    }

    @Test func knowsWhichFolderAFavouriteIsIn() throws {
        #expect(FLCategories.folder(of: try favorite("Effects/OTT"), root: db) == nil)
        #expect(FLCategories.folder(of: try favorite("Effects/Dynamics/Pro-C 3"), root: db) == "Dynamics")
    }

    @Test func movesThePictureAlongAndPutsItBack() throws {
        let ott = try favorite("Effects/OTT", picture: true)
        let moved = try FLCategories.move(ott, to: "Dynamics", root: db, journal: journal, pictures: pictures)

        #expect(moved.path == db.appendingPathComponent("Effects/Dynamics/OTT.fst").path)
        #expect(dir.exists("Plugin database/Effects/Dynamics/OTT.nfo"))
        #expect(dir.exists("Plugin database/Effects/Dynamics/OTT.png"))
        #expect(!dir.exists("Plugin database/Effects/OTT.fst"))
        // Still recorded as our picture, so "remove mine" keeps working
        #expect(pictures[moved.deletingPathExtension().appendingPathExtension("png")]?.source == .card)

        // A second move still remembers the very first place
        let again = Favorite(fst: moved, title: "OTT", section: "Effects", entry: nil)
        try FLCategories.move(again, to: "Misc", root: db, journal: journal, pictures: pictures)
        #expect(try FLCategories.restoreAll(journal: CategoryJournal(url: dir.path("categories.json")), pictures: pictures) == 1)
        #expect(dir.exists("Plugin database/Effects/OTT.fst"))
        #expect(dir.exists("Plugin database/Effects/OTT.png"))
        #expect(!dir.exists("Plugin database/Effects/Misc/OTT.fst"))
        #expect(pictures[db.appendingPathComponent("Effects/OTT.png")]?.source == .card)
    }

    @Test func takenNamesGetANumberAndTheNfoFollows() throws {
        _ = try favorite("Effects/Dynamics/Limiter")
        let limiter = try favorite("Effects/Limiter", picture: true)
        let moved = try FLCategories.move(limiter, to: "Dynamics", root: db, journal: journal, pictures: pictures)

        #expect(moved.lastPathComponent == "Limiter 2.fst")
        let nfo = try String(contentsOf: db.appendingPathComponent("Effects/Dynamics/Limiter 2.nfo"), encoding: .utf8)
        #expect(nfo.contains("Bitmap=Limiter 2.png"))
        #expect(dir.exists("Plugin database/Effects/Dynamics/Limiter.fst"))
    }

    @Test func movingBackToTheTopForgetsTheRecord() throws {
        let ott = try favorite("Effects/OTT")
        let moved = try FLCategories.move(ott, to: "Dynamics", root: db, journal: journal, pictures: pictures)
        try FLCategories.move(Favorite(fst: moved, title: "OTT", section: "Effects", entry: nil), to: nil,
                              root: db, journal: journal, pictures: pictures)
        #expect(journal.moves.isEmpty)
        #expect(dir.exists("Plugin database/Effects/OTT.fst"))
    }

    @Test func anotherFormatUnderATakenNameIsNamedAfterItsFormat() throws {
        _ = try favorite("Effects/Effect/Portal")
        let plain = try favorite("Effects/Portal")
        let entry = InstalledEntry(fst: plain.fst, section: "Effects", format: "AudioUnit",
                                   name: "Portal", vendor: "Output", files: [])
        let au = Favorite(fst: plain.fst, title: plain.title, section: plain.section, entry: entry)

        let moved = try FLCategories.move(au, to: "Effect", root: db, journal: journal, pictures: pictures)
        #expect(moved.lastPathComponent == "Portal (AU).fst")
    }
}
