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
