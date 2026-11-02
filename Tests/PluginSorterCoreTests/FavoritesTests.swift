import Foundation
import Testing
@testable import PluginSorterCore

@Suite("FL Studio favourites")
struct FavoritesTests {
    let dir: TempDir
    var db: URL { dir.path("Plugin database") }
    let plugins: URL

    init() throws {
        dir = try TempDir()
        plugins = dir.path("Plug-Ins")
        try makeBundle(plugins.appendingPathComponent("VST3/Xfer Records/OTT.vst3"), id: "com.xfer.OTT")
        try makeBundle(plugins.appendingPathComponent("VST3/Vendor/Moved.vst3"), id: "com.vendor.moved")

        try installed("Effects/VST3/OTT", name: "OTT", vendor: "Xfer Records",
                      files: [plugins.appendingPathComponent("VST3/Xfer Records/OTT.vst3").path], bom: true)
        try installed("Effects/VST3/Gone", name: "Gone", vendor: "Old Co",
                      files: [plugins.appendingPathComponent("VST3/Gone.vst3").path])
        try installed("Effects/VST3/Moved", name: "Moved", vendor: "Vendor",
                      files: [plugins.appendingPathComponent("VST3/Moved.vst3").path])
        try installed("Effects/Fruity/Fruity Limiter", name: "Fruity Limiter", vendor: "Image-Line",
                      files: ["%FLPath%/Plugins/Fruity/Effects/Fruity Limiter/Fruity Limiter_x64.dylib"])
        try installed("Effects/AudioUnit/OTT", name: "OTT", vendor: "Xfer Records", files: [], tag: "au")
        try installed("Generators/VST3/Serum 2", name: "Serum 2", vendor: "Xfer Records", files: [])

        // Favourites FL made: exact copies, one in a category folder, one renamed by the user
        try favorite("Effects/VST3/OTT", as: "Effects/OTT")
        try favorite("Effects/VST3/Gone", as: "Effects/Gone")
        try favorite("Effects/Fruity/Fruity Limiter", as: "Effects/Dynamics/Fruity Limiter")
        try FSTBuilder.make(display: "My Moved", name: "Moved", vendor: "Vendor", padding: false)
            .write(to: db.appendingPathComponent("Effects/My Moved.fst"))
    }

    private func installed(_ path: String, name: String, vendor: String, files: [String], bom: Bool = false,
                           tag: String = "") throws {
        let fst = db.appendingPathComponent("Installed/\(path).fst")
        try FileManager.default.createDirectory(at: fst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FSTBuilder.make(display: name + tag, name: name, vendor: vendor).write(to: fst)
        var lines = ["fileversion=2", "ps_name=\(name)", "ps_files=\(files.count)"]
        for (n, file) in files.enumerated() { lines.append("ps_file_filename_\(n)=\(file)") }
        lines.append("ps_file_vendorname_0=\(vendor)")
        let text = Data(lines.joined(separator: "\r\n").utf8)
        try ((bom ? Data([0xEF, 0xBB, 0xBF]) : Data()) + text).write(to: fst.deletingPathExtension().appendingPathExtension("nfo"))
    }

    private func favorite(_ installedPath: String, as path: String) throws {
        let target = db.appendingPathComponent("\(path).fst")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: db.appendingPathComponent("Installed/\(installedPath).fst"), to: target)
    }

    private var entries: [InstalledEntry] { FLFavorites.installed(root: db) }
    private func entry(_ format: String, _ name: String) throws -> InstalledEntry {
        try #require(entries.first { $0.format == format && $0.name == name })
    }

    @Test func readsWhatFLScanned() throws {
        let ott = try entry("VST3", "OTT")
        #expect(ott.section == "Effects")
        #expect(ott.vendor == "Xfer Records")
        #expect(ott.files == [plugins.appendingPathComponent("VST3/Xfer Records/OTT.vst3").path])
        #expect(try entry("Fruity", "Fruity Limiter").isNative)
        #expect(try entry("AudioUnit", "OTT").shortFormat == "AU")
        #expect(entries.count == 6)
    }

    @Test func matchesFavouritesByContentThenByName() {
        let favorites = FLFavorites.favorites(root: db, installed: entries)
        #expect(favorites.count == 4)
        let byTitle = Dictionary(uniqueKeysWithValues: favorites.map { ($0.title, $0) })
        #expect(byTitle["OTT"]?.entry?.format == "VST3")
        #expect(byTitle["Fruity Limiter"]?.isStock == true)
        #expect(byTitle["My Moved"]?.entry?.name == "Moved")  // renamed, matched by plugin name
    }

    @Test func applesAudioUnitsCountAsBuiltIn() {
        let delay = InstalledEntry(fst: db.appendingPathComponent("x.fst"), section: "Effects", format: "AudioUnit",
                                   name: "AUDelay", vendor: "Apple", files: [])
        #expect(delay.isNative)
        #expect(FLFavorites.availability(delay, bundleNames: [], audioUnits: ["other|thing"]) == .available)
    }

    @Test func stockFavouritesWithoutVendorMatchByName() throws {
        // FL's stock favourites aren't copies of the scan and their .fst carries no vendor
        try FSTBuilder.make(display: "Fruity Limiter", padding: true)
            .write(to: db.appendingPathComponent("Effects/Dynamics/Fruity Limiter.fst"))
        let limiter = try #require(FLFavorites.favorites(root: db, installed: entries).first { $0.title == "Fruity Limiter" })
        #expect(limiter.entry?.format == "Fruity")
        #expect(limiter.isStock)
    }

    @Test func availability() throws {
        let names: Set = ["OTT.vst3", "Moved.vst3"]
        func check(_ format: String, _ name: String, au: Set<String> = []) throws -> Availability {
            FLFavorites.availability(try entry(format, name), bundleNames: names, audioUnits: au)
        }
        #expect(try check("VST3", "OTT") == .available)
        #expect(try check("VST3", "Moved") == .moved)
        #expect(try check("VST3", "Gone") == .removed)
        #expect(try check("Fruity", "Fruity Limiter") == .available)
        #expect(try check("AudioUnit", "OTT") == .unknown)
        #expect(try check("AudioUnit", "OTT", au: [FLFavorites.auKey(vendor: "Xfer Records", name: "OTT")]) == .available)
        #expect(try check("AudioUnit", "OTT", au: [FLFavorites.auKey(vendor: "Other", name: "Thing")]) == .removed)
    }

    @Test func addingCopiesTheScannedEntryOnce() throws {
        let serum = try entry("VST3", "Serum 2")
        let added = try FLFavorites.add(serum, root: db)
        #expect(added == db.appendingPathComponent("Generators/Serum 2.fst"))
        #expect(try Data(contentsOf: added) == Data(contentsOf: serum.fst))
        #expect(try FLFavorites.add(serum, root: db) == db.appendingPathComponent("Generators/Serum 2 (VST3).fst"))

        // A second format of a plugin that is already a favourite gets its format in the name
        let auOTT = try FLFavorites.add(try entry("AudioUnit", "OTT"), root: db)
        #expect(auOTT.lastPathComponent == "OTT (AU).fst")
    }

    @Test func removingKeepsABackupThatCanBeRestored() throws {
        let backup = FavoriteBackup(directory: dir.path("backup"))
        let gone = try #require(FLFavorites.favorites(root: db, installed: entries).first { $0.title == "Gone" })
        try Data("Bitmap=Gone.png".utf8).write(to: gone.nfo)
        try Data([1, 2, 3]).write(to: gone.picture)

        try FLFavorites.remove(gone, backup: backup)
        for file in [gone.fst, gone.nfo, gone.picture] {
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
        #expect(backup.records.count == 3)
        #expect(FavoriteBackup(directory: dir.path("backup")).records.count == 3)  // journal survives a reload

        #expect(FLFavorites.restoreAll(backup: backup) == 1)
        for file in [gone.fst, gone.nfo, gone.picture] {
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
        #expect(backup.records.isEmpty)
    }

    @Test func restoreNeverOverwritesANewFavourite() throws {
        let backup = FavoriteBackup(directory: dir.path("backup"))
        let ott = try #require(FLFavorites.favorites(root: db, installed: entries).first { $0.title == "OTT" })
        try FLFavorites.remove(ott, backup: backup)
        try Data("new".utf8).write(to: ott.fst)

        #expect(FLFavorites.restoreAll(backup: backup) == 0)
        #expect(try Data(contentsOf: ott.fst) == Data("new".utf8))
        #expect(backup.records.count == 1)  // still restorable later
    }
}
