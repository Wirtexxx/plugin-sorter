import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Repairs for check results")
struct FixTests {
    let dir: TempDir
    var root: URL { dir.path("Plug-Ins") }

    init() throws {
        dir = try TempDir()
        let r = dir.path("Plug-Ins")
        try makeBundle(r.appendingPathComponent("VST3/Xfer Records/Serum2.vst3"), id: "com.xferrecords.Serum2")
        try makeBundle(r.appendingPathComponent("Components/Serum2.component"), id: "com.xferrecords.Serum2.au", extra: [
            "AudioComponents": [["type": "aumu", "subtype": "Xf2X", "manufacturer": "XFER", "name": "Xfer Records: Serum 2"]],
        ])
        try makeBundle(r.appendingPathComponent("Components/Vendor/Nested.component"), id: "com.vendor.nested")
        try makeBundle(r.appendingPathComponent("VST3/My Plugin.vst3"), id: "com.me.plugin")
    }

    private func bundles() -> [PluginBundle] { PluginInventory.scan(root: root).flatMap(\.bundles) }
    private func bundle(_ name: String) throws -> PluginBundle {
        try #require(bundles().first { $0.url.lastPathComponent == name })
    }
    private func fixes(_ name: String, _ issues: [PluginSorterCore.Issue]) throws -> [Fix] {
        PluginFixes.fixes(for: try bundle(name), issues: issues, installed: bundles(), root: root)
    }

    @Test func quarantineIsCleared() throws {
        let plugin = try bundle("My Plugin.vst3")
        #expect(try fixes("My Plugin.vst3", [.quarantined]) == [.unquarantine(plugin.url)])
    }

    @Test func nestedAudioUnitGoesBackToComponents() throws {
        let nested = try bundle("Nested.component")
        #expect(try fixes("Nested.component", [.notRegistered])
                == [.relocate(from: nested.url, to: root.appendingPathComponent("Components/Nested.component"))])
    }

    @Test func registeredButUnseenAudioUnitResetsTheCache() throws {
        #expect(try fixes("Serum2.component", [.notRegistered]) == [.resetAUCache])
    }

    @Test func movedDependencyIsPutBack() throws {
        let expected = root.appendingPathComponent("VST3/Serum2.vst3")
        let error = "Error: could not load \(expected.path)"
        let vst3 = try bundle("Serum2.vst3")
        let found = try fixes("Serum2.component", [.validationFailed(error)])
        #expect(found == [.relocate(from: vst3.url, to: expected)])
        #expect(PluginFixes.isDependency(found[0]))
    }

    @Test func noFixForOtherErrors() throws {
        #expect(try fixes("Serum2.component", [.validationFailed("FATAL ERROR: Initialize: result: -1")]).isEmpty)
        #expect(try fixes("My Plugin.vst3", [.loadFailed("GetPluginFactory not found"), .timeout]).isEmpty)
    }

    @Test func missingPathsWithSpacesAndPunctuation() {
        let path = root.appendingPathComponent("VST3/FabFilter Pro-Q 4.vst3").path
        #expect(PluginFixes.missingBundle(in: "could not load \(path)", root: root)?.path == path)
        #expect(PluginFixes.missingBundle(in: "failed (\(path)): no such file", root: root)?.path == path)
        #expect(PluginFixes.missingBundle(in: "could not load '\(path)'", root: root)?.path == path)
    }

    @Test func pathsInsideBundlesAndSeveralPathsInOneError() {
        let missing = root.appendingPathComponent("VST3/Serum2.vst3").path
        let other = root.appendingPathComponent("VST3/X.vst3").path
        // dlopen-style: the binary inside the bundle, then a quoted second path
        let error = "dlopen(\(missing)/Contents/MacOS/Serum2, 6): tried: '\(other)' (no such file)"
        #expect(PluginFixes.missingBundle(in: error, root: root)?.path == missing)
    }

    @Test func existingOrForeignPathsAreNotMissing() throws {
        let existing = try bundle("My Plugin.vst3").url.path
        #expect(PluginFixes.missingBundle(in: "could not load \(existing)", root: root) == nil)
        #expect(PluginFixes.missingBundle(in: "could not load /Applications/Other.vst3", root: root) == nil)
        #expect(PluginFixes.missingBundle(in: "could not load \(root.path)/VST3/../../etc.vst3", root: root) == nil)
    }

    @Test func keepListAddsEachNameOnce() throws {
        let file = dir.path("keep/keep.txt")
        PluginFixes.keep("Serum2.vst3", file: file)
        PluginFixes.keep("Other.vst3", file: file)
        PluginFixes.keep("Serum2.vst3", file: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == "Serum2.vst3\nOther.vst3\n")
    }
}
