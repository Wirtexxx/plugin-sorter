import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Script output parsing")
struct SorterParseTests {
    @Test func parsesDryRun() {
        let output = """
        == VST3
          FabFilter Pro-Q 4.vst3 -> FabFilter/
          OTT.vst3 -> Xfer Records/
          skip (Waves): WaveShell1-VST3 17.1.vst3
          keep: Serum2.vst3
          unknown vendor: Mystery.vst3
          exists: FabFilter/FabFilter Pro-C 2.vst3
        == VST
          OTT.vst -> Xfer Records/

        nested AU: 3 (run --restore-au)
        Would move: 3 (dry run, use --apply to move)
        """
        let result = Sorter.parse(output)
        #expect(result.count == 3)
        #expect(result.nestedAU == 3)
        #expect(result.moves.map(\.plugin) == ["FabFilter Pro-Q 4", "OTT", "OTT"])
        #expect(result.moves.map(\.format) == ["VST3", "VST3", "VST"])
        #expect(result.moves.map(\.vendor) == ["FabFilter", "Xfer Records", "Xfer Records"])
        #expect(result.notes.map(\.kind) == [.waves, .kept, .unknown, .exists])
        #expect(result.notes.map(\.text) == ["WaveShell1-VST3 17.1.vst3", "Serum2.vst3", "Mystery.vst3",
                                             "FabFilter/FabFilter Pro-C 2.vst3"])
    }

    @Test func parsesApplyAndUndo() {
        let applied = Sorter.parse("== VST3\n  OTT.vst3 -> Xfer Records/\n\nMoved: 1\nLog: /tmp/x.log (undo: …)\n")
        #expect(applied.count == 1)
        #expect(applied.notes.isEmpty)

        let undone = Sorter.parse("restored: VST3/Xfer Records/OTT.vst3 -> VST3/OTT.vst3\nskip: VST3/Gone.vst3\n")
        #expect(undone.moves.isEmpty)
        #expect(undone.notes.map(\.kind) == [.restored, .skipped])
    }

    @Test func componentsAreShownAsAU() {
        let result = Sorter.parse("== Components\n  OTT.component -> Xfer Records/\nWould move: 1\n")
        #expect(result.moves.first?.format == "AU")
    }
}

/// Runs scripts/sort-plugins.sh against a temporary plugin tree; nothing outside it is touched.
@Suite("sort-plugins.sh")
struct ScriptTests {
    static let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("scripts/sort-plugins.sh")

    let dir: TempDir
    var root: URL { dir.path("Plug-Ins") }

    init() throws {
        dir = try TempDir()
        let r = dir.path("Plug-Ins")
        try makeBundle(r.appendingPathComponent("VST3/FabFilter Pro-Q 4.vst3"), id: "com.fabfilter.Pro-Q.4")
        try makeBundle(r.appendingPathComponent("VST3/OTT.vst3"), id: "com.xfer.OTT")
        try makeBundle(r.appendingPathComponent("VST3/Serum2.vst3"), id: "com.xferrecords.Serum2")
        try makeBundle(r.appendingPathComponent("VST3/WaveShell1-VST3 17.1.vst3"), id: "com.WavesAudio.WaveShell1-VST3.17.1")
        try makeBundle(r.appendingPathComponent("VST3/Mystery.vst3"))
        try makeBundle(r.appendingPathComponent("VST3/kHs Gain.vst3"), id: "com.kiloHearts.kHsGain")
        try FileManager.default.createDirectory(at: r.appendingPathComponent("VST3/Kilohearts"), withIntermediateDirectories: true)
        try makeBundle(r.appendingPathComponent("VST/Portal.vst"), id: "audio.output.Portal")
        try makeBundle(r.appendingPathComponent("Components/OTT.component"), id: "com.xfer.OTT.au")
        try FileManager.default.createDirectory(at: dir.path("logs"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.path("Trash"), withIntermediateDirectories: true)
    }

    @discardableResult
    private func run(_ args: [String] = []) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.script.path] + args
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PLUGIN_SORT_ROOT": root.path,
            "PLUGIN_SORT_LOG_DIR": dir.path("logs").path,
            "PLUGIN_SORT_TRASH": dir.path("Trash").path,
            "PLUGIN_SORT_OWNER": "",
        ]) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    private func logs() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: dir.path("logs"), includingPropertiesForKeys: nil)
    }

    @Test func dryRunMovesNothing() throws {
        let (status, output) = try run()
        #expect(status == 0)
        #expect(output.contains("FabFilter Pro-Q 4.vst3 -> FabFilter/"))
        #expect(output.contains("Portal.vst -> Output/"))
        #expect(output.contains("keep: Serum2.vst3"))
        #expect(output.contains("skip (Waves): WaveShell1-VST3 17.1.vst3"))
        #expect(output.contains("unknown vendor: Mystery.vst3"))
        #expect(output.contains("Would move: 4"))
        #expect(exists("VST3/OTT.vst3"))
        #expect(try logs().isEmpty)
    }

    @Test func applySortsAndLogs() throws {
        let (status, output) = try run(["--apply"])
        #expect(status == 0)
        #expect(output.contains("Moved: 4"))
        #expect(exists("VST3/FabFilter/FabFilter Pro-Q 4.vst3"))
        #expect(exists("VST3/xfer/OTT.vst3") || exists("VST3/Xfer Records/OTT.vst3"))
        #expect(exists("VST3/Kilohearts/kHs Gain.vst3"))  // reuses the existing folder despite the case
        #expect(exists("VST/Output/Portal.vst"))
        #expect(exists("VST3/Serum2.vst3"))               // kept for its AU
        #expect(exists("Components/OTT.component"))      // Audio Units are never sorted
        #expect(try logs().count == 1)
    }

    @Test func undoRestoresEverything() throws {
        try run(["--apply"])
        let log = try #require(try logs().first)
        let (status, _) = try run(["--undo", log.path])
        #expect(status == 0)
        #expect(exists("VST3/FabFilter Pro-Q 4.vst3"))
        #expect(exists("VST/Portal.vst"))
        #expect(!exists("VST3/FabFilter"))                 // emptied vendor folders are removed
        #expect(try logs().map(\.lastPathComponent) == [log.lastPathComponent + ".undone"])
    }

    @Test func applyWithNothingToMoveSucceeds() throws {
        try run(["--apply"])
        let (status, output) = try run(["--apply"])
        #expect(status == 0)
        #expect(output.contains("Moved: 0"))
    }

    @Test func trashOnlyAcceptsPluginBundlesInsideRoot() throws {
        let outside = dir.path("outside.vst3")
        try makeBundle(outside, id: "com.outside")
        let (status, output) = try run(["--trash",
                                        root.appendingPathComponent("VST3/OTT.vst3").path,
                                        root.appendingPathComponent("VST3/../VST3/Mystery.vst3").path,
                                        outside.path])
        #expect(status == 0)
        #expect(output.contains("trashed: VST3/OTT.vst3"))
        #expect(!exists("VST3/OTT.vst3"))
        #expect(FileManager.default.fileExists(atPath: dir.path("Trash/OTT.vst3").path))
        #expect(exists("VST3/Mystery.vst3"))
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func restoreAUMovesNestedComponentsBack() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Components/Xfer Records"), withIntermediateDirectories: true)
        let original = root.appendingPathComponent("Components/OTT.component")
        let nested = root.appendingPathComponent("Components/Xfer Records/OTT.component")
        try fm.moveItem(at: original, to: nested)
        try "\(original.path)\t\(nested.path)\n".write(to: dir.path("logs/plugin-sort-20260101-000000.log"),
                                                         atomically: true, encoding: .utf8)
        #expect(try run().output.contains("nested AU: 1"))

        let (status, output) = try run(["--restore-au"])
        #expect(status == 0)
        #expect(output.contains("Restored AU: 1"))
        #expect(exists("Components/OTT.component"))
        #expect(!exists("Components/Xfer Records"))
    }
}
