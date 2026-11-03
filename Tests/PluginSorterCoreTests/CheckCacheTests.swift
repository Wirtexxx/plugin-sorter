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

    @Test func changedBundleIsCheckedAgain() throws {
        let ott = try bundle("OTT.vst3")
        let cache = CheckCache(url: file)
        cache.store([], for: ott)
        #expect(cache.issues(for: ott) == [])
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(3600)], ofItemAtPath: ott.url.path)
        #expect(cache.issues(for: ott) == nil)
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

        #expect(CheckCache.pending(bundles, cache: cache, forgotten: []).count == 2)
        cache.store([], for: one)
        #expect(CheckCache.pending(bundles, cache: cache, forgotten: [two.id]).isEmpty)
    }
}

@Suite("FL Studio")
struct FLStudioTests {
    @Test func flStudioRunningIsDetected() {
        #expect(FLStudio.isRunning(["com.apple.finder", "com.image-line.flstudio"]))
        #expect(!FLStudio.isRunning([nil, "com.apple.finder"]))
    }
}
