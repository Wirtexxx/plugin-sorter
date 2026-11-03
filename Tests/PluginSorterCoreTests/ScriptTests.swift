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
    private func run(_ args: [String] = [], extra: [String: String] = [:]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.script.path] + args
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PLUGIN_SORT_ROOT": root.path,
            "PLUGIN_SORT_LOG_DIR": dir.path("logs").path,
            "PLUGIN_SORT_TRASH": dir.path("Trash").path,
            "PLUGIN_SORT_OWNER": "",
        ].merging(extra) { $1 }) { $1 }
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
        #expect(status != 0)                               // two of the three were refused
        #expect(output.contains("trashed: VST3/OTT.vst3"))
        #expect(!exists("VST3/OTT.vst3"))
        #expect(FileManager.default.fileExists(atPath: dir.path("Trash/OTT.vst3").path))
        #expect(exists("VST3/Mystery.vst3"))
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    // MARK: - Turning plugins off

    @Test func disableMovesOutOfTheFormatFolderAndEnableBringsBack() throws {
        let path = root.appendingPathComponent("VST3/OTT.vst3").path
        #expect(try run(["--disable", path]).output.contains("disabled: VST3/OTT.vst3"))
        #expect(!exists("VST3/OTT.vst3"))
        #expect(exists("Disabled/VST3/OTT.vst3"))
        let back = root.appendingPathComponent("Disabled/VST3/OTT.vst3").path
        #expect(try run(["--enable", back]).output.contains("enabled: VST3/OTT.vst3"))
        #expect(exists("VST3/OTT.vst3"))
        #expect(!exists("Disabled/VST3"))                  // emptied folders are removed
        #expect(!exists("Disabled"))
    }

    @Test func enableNeverOverwritesAReinstalledPlugin() throws {
        try run(["--disable", root.appendingPathComponent("VST3/OTT.vst3").path])
        try makeBundle(root.appendingPathComponent("VST3/OTT.vst3"), id: "com.xfer.OTT.new")
        let output = try run(["--enable", root.appendingPathComponent("Disabled/VST3/OTT.vst3").path]).output
        #expect(output.contains("skip:"))
        #expect(!output.contains("enabled:"))
        #expect(exists("VST3/OTT.vst3"))
        #expect(exists("Disabled/VST3/OTT.vst3"))
    }

    @Test func enableRecreatesTheVendorFolder() throws {
        let nested = root.appendingPathComponent("VST3/Xfer/OTT.vst3")
        try FileManager.default.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: root.appendingPathComponent("VST3/OTT.vst3"), to: nested)
        try run(["--disable", nested.path])
        #expect(exists("Disabled/VST3/Xfer/OTT.vst3"))
        #expect(!exists("VST3/Xfer"))                      // the vendor folder went with its last plugin
        try run(["--enable", root.appendingPathComponent("Disabled/VST3/Xfer/OTT.vst3").path])
        #expect(exists("VST3/Xfer/OTT.vst3"))
        #expect(!exists("Disabled"))
    }

    @Test func disableRefusesPathsOutsideThePluginTree() throws {
        let outside = dir.path("outside.vst3")
        try makeBundle(outside, id: "com.outside")
        let hosts = "/etc/hosts"
        let output = try run(["--disable", hosts, root.appendingPathComponent("VST3/../VST3/Mystery.vst3").path,
                              outside.path]).output
        #expect(!output.contains("disabled:"))
        #expect(output.components(separatedBy: "skip:").count == 4)
        #expect(exists("VST3/Mystery.vst3"))
        #expect(FileManager.default.fileExists(atPath: outside.path))
        #expect(!exists("Disabled"))
    }

    @Test func disableAndEnableRefuseTheWrongSide() throws {
        // --enable on a plugin that isn't disabled, --disable on one that already is
        let live = root.appendingPathComponent("VST3/OTT.vst3").path
        #expect(try run(["--enable", live]).output.contains("skip:"))
        try run(["--disable", live])
        let off = root.appendingPathComponent("Disabled/VST3/OTT.vst3").path
        #expect(try run(["--disable", off]).output.contains("skip:"))
        #expect(exists("Disabled/VST3/OTT.vst3"))
        #expect(!exists("Disabled/Disabled"))
    }

    @Test func sortingIgnoresDisabledPlugins() throws {
        try run(["--disable", root.appendingPathComponent("VST3/OTT.vst3").path])
        let (_, output) = try run(["--apply"])
        #expect(!output.contains("OTT.vst3"))
        #expect(exists("Disabled/VST3/OTT.vst3"))
        #expect(!exists("Disabled/VST3/Xfer Records"))
    }

    // MARK: - Leftovers

    /// A data folder tree with a vendor folder, as /Library/Application Support has.
    private func dataTree() throws -> (roots: [String: String], vendor: URL) {
        let fm = FileManager.default
        let vendor = dir.path("Data/Support/Xfer")
        try fm.createDirectory(at: vendor.appendingPathComponent("Presets"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.path("Data/Presets/Xfer"), withIntermediateDirectories: true)
        return (["PLUGIN_SORT_DATA_ROOTS": dir.path("Data/Support").path + ":" + dir.path("Data/Presets").path], vendor)
    }

    @Test func trashDataMovesIntoTheTrash() throws {
        let (env, vendor) = try dataTree()
        let (status, output) = try run(["--trash-data", vendor.path, dir.path("Data/Presets/Xfer").path], extra: env)
        #expect(status == 0)
        #expect(output.contains("trashed-data: \(vendor.path)"))
        #expect(!FileManager.default.fileExists(atPath: vendor.path))
        #expect(FileManager.default.fileExists(atPath: dir.path("Trash/Xfer/Presets").path))
        #expect(FileManager.default.fileExists(atPath: dir.path("Trash/Xfer 2").path))   // a second one never merges
    }

    @Test func trashDataRefusesAnythingOutsideTheDataRoots() throws {
        let (env, vendor) = try dataTree()
        let outside = dir.path("Elsewhere/Xfer")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sneaky = vendor.deletingLastPathComponent().path + "/../Support/Xfer"
        let (_, output) = try run(["--trash-data", "/etc", outside.path, sneaky, vendor.path + "/./Presets"], extra: env)
        #expect(!output.contains("trashed-data:"))
        #expect(output.components(separatedBy: "skip:").count == 5)
        #expect(FileManager.default.fileExists(atPath: outside.path))
        #expect(FileManager.default.fileExists(atPath: vendor.path + "/Presets"))
    }

    @Test func trashDataRefusesTheRootItself() throws {
        let (env, _) = try dataTree()
        let rootPath = dir.path("Data/Support").path
        let (_, output) = try run(["--trash-data", rootPath, rootPath + "/"], extra: env)
        #expect(!output.contains("trashed-data:"))
        #expect(FileManager.default.fileExists(atPath: rootPath + "/Xfer"))
    }

    @Test func trashDataRefusesSymlinks() throws {
        let (env, vendor) = try dataTree()
        let target = dir.path("Elsewhere")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let link = dir.path("Data/Support/Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        // The link itself, and a path that goes through one
        try FileManager.default.createDirectory(at: target.appendingPathComponent("Inner"), withIntermediateDirectories: true)
        let (_, output) = try run(["--trash-data", link.path, link.path + "/Inner"], extra: env)
        #expect(!output.contains("trashed-data:"))
        #expect(output.components(separatedBy: "skip:").count == 3)
        #expect(FileManager.default.fileExists(atPath: target.path + "/Inner"))
        #expect(FileManager.default.fileExists(atPath: vendor.path))
    }

    @Test func forgetReceiptNeverRunsPkgutilUnderTheTestRoot() throws {
        // A pkgutil that leaves a mark when it is called at all
        let bin = dir.path("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let mark = dir.path("pkgutil-was-called")
        let fake = bin.appendingPathComponent("pkgutil")
        try "#!/bin/bash\ntouch '\(mark.path)'\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let path = bin.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
        let (status, output) = try run(["--forget-receipt", "com.xfer.OTT.pkg", "com.apple.pkg.Safari", "bad id;rm"],
                                       extra: ["PATH": path])
        #expect(status == 0)
        #expect(output.contains("forgot: com.xfer.OTT.pkg"))
        #expect(!output.contains("forgot: com.apple.pkg.Safari"))      // Apple's own receipts are never touched
        #expect(!output.contains("forgot: bad id;rm"))
        #expect(!FileManager.default.fileExists(atPath: mark.path))
    }

    @Test func oneInvocationTrashesPluginsDataAndForgetsReceipts() throws {
        let (env, vendor) = try dataTree()
        let (status, output) = try run(["--trash", root.appendingPathComponent("VST3/OTT.vst3").path,
                                        "--trash-data", vendor.path,
                                        "--forget-receipt", "com.xfer.OTT.pkg"], extra: env)
        #expect(status == 0)
        #expect(output.contains("trashed: VST3/OTT.vst3"))
        #expect(output.contains("trashed-data: \(vendor.path)"))
        #expect(output.contains("forgot: com.xfer.OTT.pkg"))
        #expect(!exists("VST3/OTT.vst3"))
        #expect(FileManager.default.fileExists(atPath: dir.path("Trash/OTT.vst3").path))
        #expect(!FileManager.default.fileExists(atPath: vendor.path))
    }

    @Test func keepFileProtectsMoreBundles() throws {
        let keep = dir.path("keep.txt")
        try "OTT.vst3\n".write(to: keep, atomically: true, encoding: .utf8)
        let (_, output) = try run(["--apply"], extra: ["PLUGIN_SORT_KEEP_FILE": keep.path])
        #expect(output.contains("keep: OTT.vst3"))
        #expect(exists("VST3/OTT.vst3"))
        #expect(exists("VST3/FabFilter/FabFilter Pro-Q 4.vst3"))
    }

    @Test func unquarantineClearsTheFlagOnlyInsideRoot() throws {
        let inside = root.appendingPathComponent("VST3/OTT.vst3")
        let outside = dir.path("outside.vst3")
        try makeBundle(outside, id: "com.outside")
        for url in [inside, outside] {
            _ = "0083;0;Safari;".withCString { setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
        }
        let (status, output) = try run(["--unquarantine", inside.path, outside.path])
        #expect(status == 0)
        #expect(output.contains("unquarantined: VST3/OTT.vst3"))
        #expect(getxattr(inside.path, "com.apple.quarantine", nil, 0, 0, 0) < 0)
        #expect(getxattr(outside.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0)
    }

    @Test func relocateMovesWithinTheTreeOnly() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("VST3/Xfer Records"), withIntermediateDirectories: true)
        let src = root.appendingPathComponent("VST3/Serum2.vst3")
        let nested = root.appendingPathComponent("VST3/Xfer Records/Serum2.vst3")
        try FileManager.default.moveItem(at: src, to: nested)

        // Refused: outside the tree, existing destination, different bundle type
        for (from, to) in [(nested.path, dir.path("Serum2.vst3").path),
                           (nested.path, root.appendingPathComponent("VST3/OTT.vst3").path),
                           (nested.path, root.appendingPathComponent("VST3/Serum2.vst").path)] {
            #expect(try run(["--relocate", from, to]).output.contains("skip:"))
        }
        #expect(exists("VST3/Xfer Records/Serum2.vst3"))

        let (status, output) = try run(["--relocate", nested.path, src.path])
        #expect(status == 0)
        #expect(output.contains("relocated: VST3/Xfer Records/Serum2.vst3 -> VST3/Serum2.vst3"))
        #expect(exists("VST3/Serum2.vst3"))
        #expect(!exists("VST3/Xfer Records"))
    }

    @Test func trashNeverNestsSameNamedBundles() throws {
        try makeBundle(dir.path("Trash/OTT.vst3"), id: "com.earlier.delete")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("VST3/Xfer"), withIntermediateDirectories: true)
        let second = root.appendingPathComponent("VST3/Xfer/OTT.vst3")
        try makeBundle(second, id: "com.xfer.OTT2")
        let (status, _) = try run(["--trash", root.appendingPathComponent("VST3/OTT.vst3").path, second.path])
        #expect(status == 0)
        let trash = try FileManager.default.contentsOfDirectory(atPath: dir.path("Trash").path).sorted()
        #expect(trash == ["OTT 2.vst3", "OTT 3.vst3", "OTT.vst3"])
        #expect(!FileManager.default.fileExists(atPath: dir.path("Trash/OTT.vst3/OTT.vst3").path))
    }

    @Test func repairsReportWhenTheyDidNothing() throws {
        let missing = root.appendingPathComponent("VST3/Missing.vst3").path
        #expect(try run(["--relocate", missing, root.appendingPathComponent("VST3/Elsewhere.vst3").path]).status != 0)
        #expect(try run(["--unquarantine", missing]).status != 0)
    }

    @Test func restoreAUAlsoMovesUnloggedNestedComponents() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Components/Vendor"), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: root.appendingPathComponent("Components/OTT.component"),
                                         to: root.appendingPathComponent("Components/Vendor/OTT.component"))
        let (status, output) = try run(["--restore-au"])
        #expect(status == 0)
        #expect(output.contains("Restored AU: 1"))
        #expect(exists("Components/OTT.component"))
        #expect(!exists("Components/Vendor"))
    }

    @Test func resetAUNeedsNoRootAndSucceeds() throws {
        let (status, output) = try run(["--reset-au"])
        #expect(status == 0)
        #expect(output.contains("AU cache reset"))
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

    // MARK: - Failure stops the rest of an uninstall

    @Test func failedTrashKeepsLeftoversAndReceipts() throws {
        let (env, vendor) = try dataTree()
        let outside = dir.path("outside.vst3")
        try makeBundle(outside, id: "com.outside")
        let (status, output) = try run(["--trash", root.appendingPathComponent("VST3/OTT.vst3").path, outside.path,
                                        "--trash-data", vendor.path, "--forget-receipt", "com.x.y"], extra: env)
        #expect(status != 0)
        #expect(output.contains("failed:"))
        #expect(!output.contains("trashed-data:"))
        #expect(!output.contains("forgot:"))
        #expect(FileManager.default.fileExists(atPath: vendor.path))
    }

    @Test func lockedBundleIsReportedAsFailed() throws {
        let (env, vendor) = try dataTree()
        let locked = root.appendingPathComponent("VST3/OTT.vst3")
        try Process.run(URL(fileURLWithPath: "/usr/bin/chflags"), arguments: ["-R", "uchg", locked.path]).waitUntilExit()
        defer { _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/chflags"), arguments: ["-R", "nouchg", locked.path]).waitUntilExit() }
        let (status, output) = try run(["--trash", locked.path, "--trash-data", vendor.path, "--forget-receipt", "com.x.y"], extra: env)
        #expect(status != 0)
        #expect(output.contains("failed: "))
        #expect(!output.contains("forgot:"))
        #expect(exists("VST3/OTT.vst3"))
        #expect(FileManager.default.fileExists(atPath: vendor.path))
    }

    @Test func extensionCaseIsMatchedLikeTheInventory() throws {
        try makeBundle(root.appendingPathComponent("VST3/Loud.VST3"), id: "com.loud")
        let (status, output) = try run(["--trash", root.appendingPathComponent("VST3/Loud.VST3").path])
        #expect(status == 0)
        #expect(output.contains("trashed: VST3/Loud.VST3"))
        #expect(!exists("VST3/Loud.VST3"))
    }

    @Test func disableReportsFailureWhenNothingMoved() throws {
        let (status, output) = try run(["--disable", root.appendingPathComponent("VST3/Nope.vst3").path])
        #expect(status != 0)
        #expect(!output.contains("disabled:"))
    }

    // MARK: - Symlinks in the plugin tree

    private func plant(_ link: String, to target: URL) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(link).deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(link), withDestinationURL: target)
    }

    @Test func commandsRefuseAPathThroughASymlinkedFolder() throws {
        let outside = dir.path("outside")
        try makeBundle(outside.appendingPathComponent("keep.vst3"), id: "com.keep")
        try plant("VST3/link", to: outside)
        let through = root.appendingPathComponent("VST3/link/keep.vst3").path
        for command in ["--disable", "--trash", "--unquarantine"] {
            let (_, output) = try run([command, through])
            #expect(output.contains("skip:"))
            #expect(!output.contains("disabled:") && !output.contains("trashed:"))
        }
        #expect(FileManager.default.fileExists(atPath: outside.appendingPathComponent("keep.vst3").path))
        #expect(!exists("Disabled"))
    }

    @Test func enableRefusesALinkedSourceAndALinkedDestination() throws {
        let outside = dir.path("outside")
        try makeBundle(outside.appendingPathComponent("keep.vst3"), id: "com.keep")
        try plant("Disabled/VST3/link", to: outside)
        let (_, source) = try run(["--enable", root.appendingPathComponent("Disabled/VST3/link/keep.vst3").path])
        #expect(source.contains("skip:") && !source.contains("enabled:"))
        // A disabled plugin whose way back leads through a link at VST3/Vendor
        try makeBundle(root.appendingPathComponent("Disabled/VST3/Vendor/Real.vst3"), id: "com.real")
        try plant("VST3/Vendor", to: outside)
        let (_, destination) = try run(["--enable", root.appendingPathComponent("Disabled/VST3/Vendor/Real.vst3").path])
        #expect(destination.contains("skip:") && !destination.contains("enabled:"))
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("Real.vst3").path))
        #expect(exists("Disabled/VST3/Vendor/Real.vst3"))
    }

    @Test func disableRefusesALinkedDisabledFolder() throws {
        let outside = dir.path("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try plant("Disabled", to: outside)
        let (_, output) = try run(["--disable", root.appendingPathComponent("VST3/OTT.vst3").path])
        #expect(output.contains("skip:"))
        #expect(exists("VST3/OTT.vst3"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    // MARK: - The script under root

    @Test func anInvalidOwnerStopsTheScript() throws {
        let sentinel = dir.path("pwned")
        let (status, output) = try run(["--trash", root.appendingPathComponent("VST3/OTT.vst3").path],
                                       extra: ["PLUGIN_SORT_OWNER": "a$(touch \(sentinel.path))"])
        #expect(status != 0)
        #expect(output.contains("Invalid owner"))
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
        #expect(exists("VST3/OTT.vst3"))
    }

    @Test func rootIgnoresTheTestOverrides() throws {
        // The tests can't run as root, so check that the script drops the overrides first thing
        let text = try String(contentsOf: Self.script, encoding: .utf8)
        let guardRange = try #require(text.range(of: "if [ \"$EUID\" -eq 0 ]; then"))
        let rootLine = try #require(text.range(of: "ROOT=\"${PLUGIN_SORT_ROOT"))
        #expect(guardRange.lowerBound < rootLine.lowerBound)
        let block = text[guardRange.lowerBound..<rootLine.lowerBound]
        for name in ["PLUGIN_SORT_ROOT", "PLUGIN_SORT_DATA_ROOTS", "PLUGIN_SORT_TRASH"] {
            #expect(block.contains(name))
        }
        #expect(!text.contains("eval "))
    }

    @Test func forgetReceiptRefusesOptionsAndAppleIds() throws {
        let (status, output) = try run(["--forget-receipt", "-rf", "--pkgs", "..", ".hidden", "COM.APPLE.y", "com.apple.z", "com.x.ok"])
        #expect(status == 0)
        #expect(output.components(separatedBy: "skip:").count == 7)
        #expect(output.contains("forgot: com.x.ok"))
    }
}
