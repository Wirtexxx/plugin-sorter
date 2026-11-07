import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Disk usage")
struct DiskUsageTests {
    let dir: TempDir

    init() throws { dir = try TempDir() }

    @Test func countsEverythingInsideABundle() throws {
        let bundle = try makeBundle(dir.path("VST3/Big.vst3"), id: "com.test.big", binary: Data(count: 200_000))
        try Data(count: 100_000).write(to: bundle.appendingPathComponent("Contents/Resources.bin"))
        let size = DiskUsage.size(of: bundle)
        #expect(size >= 300_000)
        #expect(size < 400_000)
    }

    @Test func anUnchangedBundleIsNotMeasuredAgain() throws {
        let url = try makeBundle(dir.path("VST3/Big.vst3"), id: "com.test.big", binary: Data(count: 200_000))
        let bundles = PluginInventory.scan(root: dir.url).flatMap(\.bundles)
        let id = try #require(bundles.first).id
        let first = DiskUsage.sizes(of: bundles, known: [:])
        let before = try #require(first[id]?.size)

        // Grows, but nothing that says the plugin changed: the saved size stands
        try Data(count: 500_000).write(to: url.appendingPathComponent("Contents/Resources.bin"))
        #expect(DiskUsage.sizes(of: bundles, known: first)[id]?.size == before)
        // Without a saved size it is measured for real
        #expect(try #require(DiskUsage.sizes(of: bundles, known: [:])[id]?.size) > before + 400_000)

        // An update touches the binary: measured again
        let binary = url.appendingPathComponent("Contents/MacOS/Big")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(3600)], ofItemAtPath: binary.path)
        #expect(try #require(DiskUsage.sizes(of: bundles, known: first)[id]?.size) > before + 400_000)
    }

    @Test func aRemovedBundleLeavesNoSize() throws {
        _ = try makeBundle(dir.path("VST3/Big.vst3"), id: "com.test.big")
        let bundles = PluginInventory.scan(root: dir.url).flatMap(\.bundles)
        let id = try #require(bundles.first).id
        let known = DiskUsage.sizes(of: bundles, known: [:])
        #expect(known[id] != nil)
        #expect(DiskUsage.sizes(of: [], known: known)[id] == nil)
    }

    @Test func sizeOfAFileAndOfNothing() throws {
        let file = dir.path("file.bin")
        try Data(count: 50_000).write(to: file)
        #expect(DiskUsage.size(of: file) >= 50_000)
        #expect(DiskUsage.size(of: dir.path("missing")) == 0)
    }

    @Test func findsDeveloperFoldersByName() throws {
        let support = dir.path("Application Support")
        let presets = dir.path("Presets")
        for folder in [support.appendingPathComponent("FabFilter"), support.appendingPathComponent("Valhalla DSP"),
                       support.appendingPathComponent("Xfer"), support.appendingPathComponent("Apple"),
                       support.appendingPathComponent("Plugin Sorter"), support.appendingPathComponent("u-he"),
                       support.appendingPathComponent("Out"), presets.appendingPathComponent("FabFilter")] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let roots = [support, presets]
        func names(_ vendor: String) -> [String] {
            DiskUsage.vendorFolders(for: vendor, in: roots).map { "\($0.deletingLastPathComponent().lastPathComponent)/\($0.lastPathComponent)" }
        }
        #expect(names("FabFilter") == ["Application Support/FabFilter", "Presets/FabFilter"])
        #expect(names("Valhalla DSP, LLC") == ["Application Support/Valhalla DSP"])
        #expect(names("Xfer Records") == ["Application Support/Xfer"])
        #expect(names("u-he") == ["Application Support/u-he"])
        #expect(names("Output").isEmpty)        // "Out" is too short to count as a prefix
        #expect(names("Apple").isEmpty)         // system folders are never a developer's data
        #expect(names("").isEmpty)
    }
}
