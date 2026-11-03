import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Saved check results")
struct CheckCacheTests {
    let dir: TempDir
    var file: URL { dir.path("checks.json") }

    init() throws {
        dir = try TempDir()
        try makeBundle(dir.path("Plug-Ins/VST3/Xfer Records/OTT.vst3"), id: "com.xfer.OTT")
        try makeBundle(dir.path("Plug-Ins/VST3/Vendor/Other.vst3"), id: "com.vendor.other")
    }

    private func bundle(_ name: String) throws -> PluginBundle {
        let bundles = PluginInventory.scan(root: dir.path("Plug-Ins")).flatMap(\.bundles)
        return try #require(bundles.first { $0.url.lastPathComponent == name })
    }

    @Test func storedResultSurvivesReload() throws {
        let ott = try bundle("OTT.vst3")
        CheckCache(url: file).store([.quarantined, .loadFailed("x")], for: ott)
        #expect(CheckCache(url: file).issues(for: ott) == [.quarantined, .loadFailed("x")])
    }

    @Test func savedResultsCoverOnlyUnchangedBundles() throws {
        let ott = try bundle("OTT.vst3"), other = try bundle("Other.vst3")
        let cache = CheckCache(url: file)
        cache.store([.quarantined], for: ott)
        #expect(cache.saved(for: [ott, other]) == [ott.id: [.quarantined]])
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(3600)], ofItemAtPath: ott.url.path)
        #expect(cache.saved(for: [ott, other]).isEmpty)
    }

    @Test func changedBundleIsCheckedAgain() throws {
        let ott = try bundle("OTT.vst3")
        let cache = CheckCache(url: file)
        cache.store([], for: ott)
        #expect(cache.issues(for: ott) == [])
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(3600)], ofItemAtPath: ott.url.path)
        #expect(cache.issues(for: ott) == nil)
    }

    @Test func binaryReplacedInsideTheBundleIsCheckedAgain() throws {
        // A .pkg update rewrites Contents/MacOS/<binary>; the bundle folder's own date stays the same
        let ott = try bundle("OTT.vst3")
        let cache = CheckCache(url: file)
        cache.store([], for: ott)
        let binary = try #require(ott.executable)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(7200)], ofItemAtPath: binary.path)
        #expect(cache.issues(for: ott) == nil)
    }

    @Test func passingFailuresAreNotRemembered() throws {
        // A timeout or an unregistered AU says more about the moment than about the plugin
        let ott = try bundle("OTT.vst3")
        let cache = CheckCache(url: file)
        cache.store([.timeout], for: ott)
        #expect(cache.issues(for: ott) == nil)
        cache.store([.notRegistered], for: ott)
        #expect(cache.issues(for: ott) == nil)
        cache.store([.quarantined], for: ott)
        #expect(cache.issues(for: ott) == [.quarantined])
    }

    @Test func unknownBundleHasNoResult() throws {
        #expect(CheckCache(url: file).issues(for: try bundle("OTT.vst3")) == nil)
    }

    @Test func clearForgetsEverything() throws {
        let ott = try bundle("OTT.vst3")
        let cache = CheckCache(url: file)
        cache.store([], for: ott)
        cache.clear()
        #expect(cache.issues(for: ott) == nil)
        #expect(CheckCache(url: file).issues(for: ott) == nil)
    }
}

@Suite("Background check queue")
struct CheckQueueTests {
    @Test func forgottenBundlesLeaveTheQueue() throws {
        let dir = try TempDir()
        try makeBundle(dir.path("Plug-Ins/VST3/A/One.vst3"), id: "com.a.one")
        try makeBundle(dir.path("Plug-Ins/VST3/B/Two.vst3"), id: "com.b.two")
        let bundles = PluginInventory.scan(root: dir.path("Plug-Ins")).flatMap(\.bundles)
        let one = try #require(bundles.first { $0.url.lastPathComponent == "One.vst3" })
        let two = try #require(bundles.first { $0.url.lastPathComponent == "Two.vst3" })
        let cache = CheckCache(url: dir.path("checks.json"))

        #expect(CheckCache.pending(bundles, saved: cache.saved(for: bundles), forgotten: []).count == 2)
        cache.store([], for: one)
        #expect(CheckCache.pending(bundles, saved: cache.saved(for: bundles), forgotten: [two.id]).isEmpty)
    }

    @Test func disabledBundlesAreNotQueuedForChecks() throws {
        let dir = try TempDir()
        try makeBundle(dir.path("Plug-Ins/VST3/A/One.vst3"), id: "com.a.one")
        try makeBundle(dir.path("Plug-Ins/Disabled/Components/One.component"), id: "com.a.one.au")
        let plugin = try #require(PluginInventory.scan(root: dir.path("Plug-Ins")).first)
        #expect(plugin.bundles.count == 2)
        #expect(plugin.activeBundles.map(\.format) == [.vst3])
        let pending = CheckCache.pending(plugin.activeBundles, saved: [:], forgotten: [])
        #expect(pending.map(\.format) == [.vst3])
    }
}

@Suite("FL Studio")
struct FLStudioTests {
    @Test func flStudioRunningIsDetected() {
        #expect(FLStudio.isRunning(["com.apple.finder", "com.image-line.flstudio"]))
        #expect(!FLStudio.isRunning([nil, "com.apple.finder"]))
    }
}

@Suite("Known without a check")
struct KnownIssueTests {
    @Test func nestedAudioUnitIsUnregisteredStraightAway() throws {
        let dir = try TempDir()
        try makeBundle(dir.path("Plug-Ins/Components/Vendor/Nested.component"), id: "com.vendor.nested")
        try makeBundle(dir.path("Plug-Ins/Components/Flat.component"), id: "com.vendor.flat")
        let bundles = PluginInventory.scan(root: dir.path("Plug-Ins")).flatMap(\.bundles)
        let nested = try #require(bundles.first { $0.url.lastPathComponent == "Nested.component" })
        let flat = try #require(bundles.first { $0.url.lastPathComponent == "Flat.component" })
        #expect(PluginChecker.knownIssues(nested) == [.notRegistered])
        #expect(PluginChecker.knownIssues(flat) == nil)
    }
}
