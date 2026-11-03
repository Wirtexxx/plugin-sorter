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

    @Test func fruityPluginsAreLeftOut() {
        #expect(!rows().contains { $0.name == "Fruity Limiter" })
        #expect(rows().count == 4)
    }
}
