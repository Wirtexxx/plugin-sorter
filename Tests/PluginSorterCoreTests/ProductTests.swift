import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Hosts that have plugins open")
struct HostAppsTests {
    @Test func anyKnownHostCounts() {
        #expect(HostApps.running(["com.ableton.live", "com.apple.finder", nil]) == ["Ableton Live"])
        #expect(HostApps.running(["com.image-line.flstudio"]) == ["FL Studio"])
        #expect(HostApps.running(["com.steinberg.cubase14", "com.cockos.reaper"]) == ["Cubase", "REAPER"])
    }

    @Test func eachIsNamedOnce() {
        #expect(HostApps.running(["com.steinberg.cubase13", "com.steinberg.cubase14"]) == ["Cubase"])
    }

    @Test func nothingElseCounts() {
        #expect(HostApps.running(["com.apple.Safari", "com.apple.finder"]).isEmpty)
    }
}

@Suite("Banners")
struct BannerTests {
    @Test func anErrorStaysUntilClosed() {
        #expect(!Banner(source: .manager(.failed("x")), isError: true, undo: nil).fades)
    }

    @Test func aResultWithUndoStays() {
        #expect(!Banner(source: .sorter(.moved(1)), isError: false, undo: {}).fades)
    }

    @Test func aPlainResultFades() {
        #expect(Banner(source: .sorter(.moved(1)), isError: false, undo: nil).fades)
    }

    @Test func aCancelIsNeitherASuccessNorAnError() {
        #expect(Banner(source: .sorter(.cancelled), isError: false, undo: nil).tone == .info)
        #expect(Banner(source: .manager(.cancelled), isError: false, undo: nil).tone == .info)
        #expect(Banner(source: .manager(.notSeenByFL), isError: false, undo: nil).tone == .info)
        #expect(Banner(source: .sorter(.moved(1)), isError: false, undo: nil).tone == .success)
        #expect(Banner(source: .manager(.failed("x")), isError: true, undo: nil).tone == .error)
    }
}

@Suite("What an empty list says")
struct EmptyListTests {
    @Test func aSearchWithoutResultsOffersAWayBack() {
        #expect(EmptyList(query: "x", filter: .all, plugins: 5) == .noMatches)
        #expect(EmptyList(query: "", filter: .disabled, plugins: 5) == .noMatches)
    }

    @Test func nothingInstalledIsSaidAsSuch() {
        #expect(EmptyList(query: "", filter: .all, plugins: 0) == .noPlugins)
    }
}

@Suite("Cleanup and separate products")
struct CleanupProductTests {
    private func plugin(_ name: String) -> ManagedPlugin {
        let bundle = PluginBundle(url: URL(fileURLWithPath: "/p/\(name).vst3"), format: .vst3, vendor: "Xfer Records", version: "1",
                                  executable: nil, archs: [], quarantined: false, au: nil, nested: false)
        return ManagedPlugin(key: name, name: name, vendor: "Xfer Records", bundles: [bundle])
    }

    @Test func serum2DoesNotReplaceSerum() {
        #expect(Cleanup.findings([plugin("Serum"), plugin("Serum2")]).isEmpty)
        #expect(Cleanup.findings([plugin("Serum"), plugin("Serum 2")]).isEmpty)
    }
}

@Suite("Installer receipts that stay")
struct ReceiptSafetyTests {
    private func plugin(_ name: String, id: String) -> ManagedPlugin {
        let bundle = PluginBundle(url: URL(fileURLWithPath: "/p/\(name).vst3"), format: .vst3, vendor: "V", version: "1", executable: nil,
                                  archs: [], quarantined: false, au: nil, nested: false,
                                  idVendor: PluginInventory.idVendor(id), bundleID: id)
        return ManagedPlugin(key: name, name: name, vendor: "V", bundles: [bundle])
    }

    private let file = "Library/Audio/Plug-Ins/VST3/Comp.vst3"

    @Test func aReceiptThatInstalledAnAppStays() {
        let receipt = Receipt(id: "com.acme.suite.pkg", files: [file], installsApp: true)
        #expect(Uninstall.forgettable([receipt], removing: plugin("Comp", id: "com.acme.comp"), others: []).isEmpty)
    }

    @Test func anotherDevelopersFileOfTheSameNameStays() {
        let receipt = Receipt(id: "com.other.comp.pkg", files: [file])
        #expect(Uninstall.forgettable([receipt], removing: plugin("Comp", id: "com.acme.comp"), others: []).isEmpty)
    }

    @Test func theDevelopersOwnReceiptGoes() {
        let receipt = Receipt(id: "com.acme.comp.pkg", files: [file])
        #expect(Uninstall.forgettable([receipt], removing: plugin("Comp", id: "com.acme.comp"), others: []) == [receipt])
    }

    @Test func anAppInTheListIsNoticed() {
        #expect(Uninstall.installsApp(["Applications/Acme.app/Contents/Info.plist", file]))
        #expect(!Uninstall.installsApp([file, "Library/Application Support/Acme/x.bin"]))
    }
}

@Suite("Plugins in the user's own Library")
struct UserLevelTests {
    let dir: TempDir
    var system: URL { dir.path("System") }
    var user: URL { dir.path("User") }

    init() throws {
        dir = try TempDir()
        try makeBundle(system.appendingPathComponent("VST3/A.vst3"), id: "com.a.a")
        try makeBundle(user.appendingPathComponent("VST3/B.vst3"), id: "com.b.b")
        try makeBundle(user.appendingPathComponent("Disabled/VST/C.vst"), id: "com.c.c")
    }

    private func scan() -> [ManagedPlugin] { PluginInventory.scan(root: system, userRoot: user) }
    private func bundle(_ name: String) throws -> PluginBundle {
        try #require(scan().flatMap(\.bundles).first { $0.url.lastPathComponent == name })
    }

    @Test func bothPlacesAreFound() throws {
        #expect(scan().map(\.name) == ["A", "B", "C"])
        #expect(try !bundle("A.vst3").isUserLevel)
        #expect(try bundle("B.vst3").isUserLevel)
        #expect(try bundle("C.vst").isDisabled)
    }

    @Test func thePathSaysWhichPlace() throws {
        #expect(try bundle("A.vst3").displayPath == "VST3/A.vst3")
        #expect(try bundle("B.vst3").displayPath == "~/VST3/B.vst3")
    }

    @Test func turningOffAndOnNeedsNoAdministrator() throws {
        try UserPlugins.setDisabled(bundle("B.vst3"), true, root: user)
        #expect(dir.exists("User/Disabled/VST3/B.vst3"))
        #expect(!dir.exists("User/VST3/B.vst3"))
        try UserPlugins.setDisabled(bundle("B.vst3"), false, root: user)
        #expect(dir.exists("User/VST3/B.vst3"))
    }

    @Test func nothingIsOverwritten() throws {
        try makeBundle(user.appendingPathComponent("VST/C.vst"), id: "com.c.c")
        let disabled = try #require(scan().flatMap(\.bundles).first { $0.isDisabled })
        #expect(throws: (any Error).self) { try UserPlugins.setDisabled(disabled, false, root: user) }
        #expect(dir.exists("User/Disabled/VST/C.vst"))
    }

    @Test func quarantineComesOffInPlace() throws {
        let url = user.appendingPathComponent("VST3/B.vst3")
        _ = "0083;0;Safari;".withCString { setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
        try UserPlugins.unquarantine(url)
        #expect(getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) < 0)
    }

    @Test func aNestedAudioUnitGoesBackToTheUsersComponents() throws {
        try makeBundle(user.appendingPathComponent("Components/Vendor/N.component"), id: "com.n.n")
        let nested = try bundle("N.component")
        let fixes = PluginFixes.fixes(for: nested, issues: [.notRegistered], installed: [], root: system, userRoot: user)
        #expect(fixes == [.relocate(from: nested.url, to: user.appendingPathComponent("Components/N.component"))])
    }
}

private func bundles(_ dir: TempDir, _ names: String...) throws -> [PluginBundle] {
    try names.map { name in
        let url = try makeBundle(dir.path(name), id: "com.x." + name)
        return PluginBundle(url: url, format: .vst3, vendor: "X", version: "1", executable: nil, archs: [], quarantined: false,
                            au: nil, nested: false)
    }
}

private func plugin(_ bundles: [PluginBundle]) -> ManagedPlugin {
    ManagedPlugin(key: "x", name: "X", vendor: "X", bundles: bundles)
}

@Suite("What the manager reports")
@MainActor struct ManagerOutcomeTests {
    let dir: TempDir
    init() throws { dir = try TempDir() }

    private func manager(answer: Shell.Result, trasher: @escaping (URL) throws -> Void = { _ in }) -> ManagerLibrary {
        ManagerLibrary(cache: CheckCache(url: dir.path("checks.json")), runner: { _, _, _ in answer }, inventory: { [] },
                       checker: { _ in [] }, trasher: trasher, userRoot: dir.path("User"))
    }

    private func finish(_ manager: ManagerLibrary) async {
        await wait { !manager.busy }
    }

    @Test func partOfATurnOffIsReportedAsPart() async throws {
        let manager = manager(answer: Shell.Result(status: 1, output: "disabled: VST3/A.vst3\nskip: /x/B.vst3\n", error: "x"))
        manager.setDisabled(plugin(try bundles(dir, "A.vst3", "B.vst3")), true)
        await finish(manager)
        #expect(manager.status == .partly(done: 1, failed: ["/x/B.vst3"]))
    }

    @Test func leftoversThatStayedAreReported() async throws {
        let answer = Shell.Result(status: 0, output: "trashed: VST3/A.vst3\nfailed: /Library/Application Support/X\n", error: "")
        let manager = manager(answer: answer)
        manager.uninstall(plugin(try bundles(dir, "A.vst3")), leftovers: [], receipts: [])
        await finish(manager)
        #expect(manager.status == .partly(done: 1, failed: ["/Library/Application Support/X"]))
    }

    @Test func ownLeftoversThatWontGoAreReported() async throws {
        struct Refused: Error {}
        let home = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Preferences/x.plist")
        let leftover = Leftover(url: home, kind: .preferences, preselected: true)
        let manager = manager(answer: Shell.Result(status: 0, output: "trashed: VST3/A.vst3\n", error: ""), trasher: { _ in throw Refused() })
        manager.uninstall(plugin(try bundles(dir, "A.vst3")), leftovers: [leftover], receipts: [])
        await finish(manager)
        #expect(manager.status == .partly(done: 1, failed: [home.path]))
    }

    @Test func aFailedRemovalLeavesTheLeftovers() async throws {
        var trashed: [URL] = []
        let home = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Preferences/x.plist")
        let manager = manager(answer: Shell.Result(status: 1, output: "failed: VST3/A.vst3\n", error: "x"), trasher: { trashed.append($0) })
        manager.uninstall(plugin(try bundles(dir, "A.vst3")), leftovers: [Leftover(url: home, kind: .preferences, preselected: true)], receipts: [])
        await finish(manager)
        #expect(trashed.isEmpty)
    }

    @Test func aCancelStaysACancel() async throws {
        let manager = manager(answer: Shell.Result(status: 1, output: "", error: "execution error: User canceled. (-128)"))
        manager.trash(try bundles(dir, "A.vst3"))
        await finish(manager)
        #expect(manager.status == .cancelled)
    }

    @Test func aUserLevelPluginGoesWithoutTheScript() async throws {
        var scriptRuns = 0
        var trashed: [URL] = []
        let url = try makeBundle(dir.path("User/VST3/B.vst3"), id: "com.b.b")
        var bundle = PluginBundle(url: url, format: .vst3, vendor: "X", version: "1", executable: nil, archs: [], quarantined: false,
                                  au: nil, nested: false)
        bundle.isUserLevel = true
        let manager = ManagerLibrary(cache: CheckCache(url: dir.path("checks.json")),
                                     runner: { _, _, _ in scriptRuns += 1; return Shell.Result(status: 0, output: "", error: "") },
                                     inventory: { [] }, checker: { _ in [] }, trasher: { trashed.append($0) }, userRoot: dir.path("User"))
        manager.trash([bundle])
        await finish(manager)
        #expect(scriptRuns == 0)
        #expect(trashed == [url])
        #expect(manager.status == .trashed(1))
    }
}

@Suite("The window without FL Studio")
@MainActor struct WithoutFLTests {
    let dir: TempDir
    init() throws { dir = try TempDir() }

    private struct NoSecrets: SecretStore {
        func accounts() throws -> Set<String> { [] }
        func read(_ account: String) throws -> Data? { nil }
        func write(_ data: Data, account: String) throws {}
        func delete(_ account: String) throws {}
    }

    private func model() -> AppModel {
        let model = AppModel(sorter: Sorter(demo: true), manager: ManagerLibrary(demo: true, cache: CheckCache(url: dir.path("c.json"))),
                             favorites: FavoritesLibrary(demoEntries: [], favorites: [], storage: dir.path("fav")),
                             pictures: FLLibrary(demo: true), known: KnownPlugins(url: dir.path("k.json")),
                             labels: UserLabels(url: dir.path("l.json")), vault: LicenseVault(store: NoSecrets()))
        model.flRoot = dir.path("no FL here")
        return model
    }

    @Test func noFLDatabaseMeansNoFLInTheWindow() {
        #expect(!model().usesFL)
    }

    @Test func aFLDatabaseBringsItBack() throws {
        let model = model()
        try FileManager.default.createDirectory(at: dir.path("db"), withIntermediateDirectories: true)
        model.flRoot = dir.path("db")
        #expect(model.usesFL)
    }

    @Test func tasksDontWaitForFL() {
        #expect(model().tasksAllDone)
    }
}

@Suite("Colours people can read")
struct ContrastTests {
    @Test func secondaryTextIsReadableOnEverySurface() {
        for surface in [Palette.chassis, Palette.inset, Palette.panel, Palette.raised] {
            #expect(Palette.contrast(Palette.label, surface) >= 4.5)
            #expect(Palette.contrast(Palette.text, surface) >= 4.5)
        }
    }

    @Test func controlsThatStillWorkCanBeSeen() {
        for surface in [Palette.chassis, Palette.inset, Palette.panel, Palette.raised] {
            #expect(Palette.contrast(Palette.dim, surface) >= 3)
        }
    }
}

@Suite("Words for what colours say")
struct StateWordsTests {
    @Test func everyStateHasAWordInEveryLanguage() {
        for lang in Lang.allCases {
            let t = L10n(lang: lang)
            for level in [CheckState.Level.ok, .warning, .failed] { #expect(!t.level(level).hasPrefix("level.")) }
            #expect(!t.level(nil).hasPrefix("level."))
        }
    }
}
