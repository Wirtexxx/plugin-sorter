import Foundation
import Testing
@testable import PluginSorterCore

@Suite("One row per plugin")
struct CatalogTests {
    let dir: TempDir
    var db: URL { dir.path("Plugin database") }
    var plugins: URL { dir.path("Plug-Ins") }

    init() throws {
        dir = try TempDir()
        try makeBundle(plugins.appendingPathComponent("VST3/Xfer Records/OTT.vst3"), id: "com.xfer.OTT")
        try makeBundle(plugins.appendingPathComponent("Components/OTT.component"), id: "com.xfer.OTTAU", extra: [
            "AudioComponents": [["type": "aufx", "subtype": "XOTT", "manufacturer": "XfeR", "name": "Xfer Records: OTT"]],
        ])
        try makeBundle(plugins.appendingPathComponent("VST3/FabFilter/FabFilter Pro-Q 4.vst3"), id: "com.fabfilter.Pro-Q.4")
        try makeBundle(plugins.appendingPathComponent("VST3/oeksound/soothe2.vst3"), id: "com.oeksound.soothe2")

        try installed("Effects/VST3/OTT", name: "OTT", vendor: "Xfer Records",
                      files: [plugins.appendingPathComponent("VST3/Xfer Records/OTT.vst3").path])
        try installed("Effects/AudioUnit/OTT", name: "OTT", vendor: "Xfer Records", files: [])
        try installed("Effects/AudioUnit/Pro-Q 4", name: "Pro-Q 4", vendor: "FabFilter", files: [])
        try installed("Effects/VST3/Gone", name: "Gone", vendor: "Old Co",
                      files: [plugins.appendingPathComponent("VST3/Gone.vst3").path])
        try installed("Effects/Fruity/Fruity Limiter", name: "Fruity Limiter", vendor: "Image-Line",
                      files: ["%FLPath%/Plugins/Fruity/Effects/Fruity Limiter/Fruity Limiter_x64.dylib"])

        try favorite("Effects/VST3/OTT", as: "Effects/OTT")
        try favorite("Effects/VST3/Gone", as: "Effects/Gone")
        try favorite("Effects/Fruity/Fruity Limiter", as: "Effects/Dynamics/Fruity Limiter")
    }

    private func installed(_ path: String, name: String, vendor: String, files: [String]) throws {
        let fst = db.appendingPathComponent("Installed/\(path).fst")
        try FileManager.default.createDirectory(at: fst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FSTBuilder.make(display: name + path, name: name, vendor: vendor).write(to: fst)
        var lines = ["ps_name=\(name)", "ps_file_vendorname_0=\(vendor)"]
        for (n, file) in files.enumerated() { lines.append("ps_file_filename_\(n)=\(file)") }
        try Data(lines.joined(separator: "\n").utf8).write(to: fst.deletingPathExtension().appendingPathExtension("nfo"))
    }

    private func favorite(_ installedPath: String, as path: String) throws {
        let target = db.appendingPathComponent("\(path).fst")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: db.appendingPathComponent("Installed/\(installedPath).fst"), to: target)
    }

    private func rows() -> [CatalogRow] {
        let entries = FLFavorites.installed(root: db)
        let removed = Set(entries.filter { $0.name == "Gone" }.map(\.id))
        return PluginCatalog.rows(plugins: PluginInventory.scan(root: plugins), entries: entries,
                                  favorites: FLFavorites.favorites(root: db, installed: entries), removed: removed)
    }

    private func row(_ name: String) throws -> CatalogRow {
        try #require(rows().first { $0.name == name })
    }

    @Test func aRowKeepsItsFavouritesInTheOrderGiven() throws {
        try favorite("Effects/AudioUnit/OTT", as: "Effects/OTT AU")
        let entries = FLFavorites.installed(root: db)
        let favorites = FLFavorites.favorites(root: db, installed: entries)
        let found = { (list: [Favorite]) -> [String] in
            let rows = PluginCatalog.rows(plugins: PluginInventory.scan(root: plugins), entries: entries, favorites: list, removed: [])
            return rows.first { $0.name == "OTT" }?.favorites.map(\.id) ?? []
        }
        #expect(found(favorites).count == 2)
        #expect(found(favorites) == found(favorites.reversed()).reversed())
    }

    @Test func vst3EntryJoinsByPath() throws {
        let ott = try row("OTT")
        #expect(ott.plugin != nil)
        #expect(ott.isKnownToFL)
        #expect(ott.entries.contains { $0.format == "VST3" })
        #expect(ott.isFavorite)
    }

    @Test func audioUnitEntryJoinsByVendorAndName() throws {
        #expect(try row("OTT").entries.count == 2)
        // The vendor prefix in the file name doesn't keep FL's "Pro-Q 4" away from it
        let proQ = try row("FabFilter Pro-Q 4")
        #expect(proQ.entries.map(\.name) == ["Pro-Q 4"])
        #expect(rows().filter { $0.name.contains("OTT") }.count == 1)
    }

    @Test func diskOnlyPluginHasNoEntries() throws {
        let soothe = try row("soothe2")
        #expect(!soothe.isKnownToFL)
        #expect(!soothe.isFavorite)
        #expect(!soothe.isStale)
    }

    @Test func deletedFavouriteBecomesStaleRow() throws {
        let gone = try row("Gone")
        #expect(gone.plugin == nil)
        #expect(gone.isStale)
        #expect(gone.isFavorite)
    }

    @Test func pluginsElsewhereStillGetARow() throws {
        // FL also finds plugins outside /Library/Audio/Plug-Ins, e.g. in ~/Library; they stay reachable
        try installed("Effects/VST3/Elsewhere", name: "Elsewhere", vendor: "Home Co",
                      files: [dir.path("home/Elsewhere.vst3").path])
        let elsewhere = try row("Elsewhere")
        #expect(elsewhere.plugin == nil)
        #expect(!elsewhere.isStale)
        #expect(elsewhere.isKnownToFL)
    }

    @Test func fruityPluginsAreLeftOut() {
        #expect(!rows().contains { $0.name == "Fruity Limiter" })
        #expect(rows().count == 4)
    }

    @Test func disabledPluginStaysJoinedToFL() throws {
        // FL's entry still names the file where it used to be; only that path ties it to "Disk Name"
        try makeBundle(plugins.appendingPathComponent("Disabled/VST3/Zed/Disk Name.vst3"), id: "com.zed.disk")
        // The scan reports /private/var/…, where the temporary folder says /var/…
        let tree = plugins.path.hasPrefix("/var/") ? "/private" + plugins.path : plugins.path
        try installed("Effects/VST3/Wobbly", name: "Wobbly", vendor: "Other Co",
                      files: [tree + "/VST3/Zed/Disk Name.vst3"])
        try favorite("Effects/VST3/Wobbly", as: "Effects/Wobbly")
        let entries = FLFavorites.installed(root: db)
        // Whatever the file check says about the old path, the plugin is not gone
        let removed = Set(entries.map(\.id))
        let all = PluginCatalog.rows(plugins: PluginInventory.scan(root: plugins), entries: entries,
                                     favorites: FLFavorites.favorites(root: db, installed: entries), removed: removed)
        let row = try #require(all.first { $0.name == "Disk Name" })
        #expect(row.plugin?.isDisabled == true)
        #expect(!row.isStale)
        #expect(!row.entries.isEmpty)
        #expect(row.isFavorite)
        #expect(!all.contains { $0.name == "Wobbly" })
    }

    @Test func disabledAudioUnitIsNeitherDeletedNorStale() throws {
        // FL lists an AU without a path, by its own name; the file is called something else
        try makeBundle(plugins.appendingPathComponent("Disabled/Components/iZOzone11ClarityAUHook.component"), id: "com.izotope.clarity", extra: [
            "AudioComponents": [["type": "aufx", "subtype": "Clar", "manufacturer": "iZtp", "name": "iZotope: Ozone 11 Clarity"]],
        ])
        try installed("Effects/AudioUnit/Clarity", name: "Ozone 11 Clarity", vendor: "iZotope", files: [])
        try favorite("Effects/AudioUnit/Clarity", as: "Effects/Ozone 11 Clarity")
        let entries = FLFavorites.installed(root: db)
        let scanned = PluginInventory.scan(root: plugins)

        // The availability check: the registry no longer lists it, the turned-off file does
        let entry = try #require(entries.first { $0.name == "Ozone 11 Clarity" })
        let registry: Set<String> = [FLFavorites.auKey(vendor: "Xfer Records", name: "OTT")]
        #expect(FLFavorites.availability(entry, bundleNames: [], audioUnits: registry) == .removed)
        #expect(FLFavorites.availability(entry, bundleNames: [],
                                         audioUnits: registry.union(FLFavorites.disabledAudioUnitKeys(scanned))) == .available)

        // And even if it were reported removed, the row stays the plugin's, not a "deleted" one
        let all = PluginCatalog.rows(plugins: scanned, entries: entries,
                                     favorites: FLFavorites.favorites(root: db, installed: entries), removed: [entry.id])
        let row = try #require(all.first { $0.plugin?.isDisabled == true })
        #expect(!row.isStale)
        #expect(row.entries.map(\.name) == ["Ozone 11 Clarity"])
        #expect(!all.contains { $0.isStale && $0.name == "Ozone 11 Clarity" })
    }

    @Test func everyWavesPluginInAShellGetsItsOwnRow() throws {
        let shell = plugins.appendingPathComponent("VST3/WaveShell1-VST3 17.1.vst3")
        try makeBundle(shell, id: "com.WavesAudio.WaveShell1-VST3.17.1")
        try installed("Effects/VST3/CLA-76 Stereo", name: "CLA-76 Stereo", vendor: "Waves", files: [shell.path])
        try installed("Effects/VST3/SSLComp Stereo", name: "SSLComp Stereo", vendor: "Waves", files: [shell.path])
        try favorite("Effects/VST3/CLA-76 Stereo", as: "Effects/Dynamics/CLA-76 Stereo")
        try favorite("Effects/VST3/SSLComp Stereo", as: "Effects/Dynamics/SSLComp Stereo")

        let cla = try row("CLA-76 Stereo")
        #expect(cla.entries.map(\.name) == ["CLA-76 Stereo"])
        #expect(cla.favorites.map(\.title) == ["CLA-76 Stereo"])
        #expect(!cla.isStale)
        #expect(try row("SSLComp Stereo").favorites.map(\.title) == ["SSLComp Stereo"])
        #expect(try row("WaveShell1-VST3 17.1").entries.isEmpty)
    }

    @Test func twoNamesInAnOrdinaryBundleStayOnePlugin() throws {
        let serum = plugins.appendingPathComponent("VST3/Serum2.vst3")
        try makeBundle(serum, id: "com.xfer.serum2")
        try installed("Generators/VST3/Serum 2", name: "Serum 2", vendor: "Xfer Records", files: [serum.path])
        try installed("Effects/VST3/Serum 2 FX", name: "Serum 2 FX", vendor: "Xfer Records", files: [serum.path])

        #expect(try row("Serum2").entries.count == 2)
    }
}
