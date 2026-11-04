import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Screenshots kept by the app")
struct LocalPicturesTests {
    private let dir: TempDir
    private var folder: URL { dir.path("Pictures") }

    init() throws { dir = try TempDir() }

    private func plugin(_ key: String, formats: [PluginFormat] = [.au], disabled: Bool = false) -> ManagedPlugin {
        let bundles = formats.map { format in
            PluginBundle(url: URL(fileURLWithPath: "/p/\(key).\(format.fileExtension)"), format: format, vendor: "V",
                         version: "1", executable: nil, archs: [], quarantined: false, au: nil, nested: false,
                         isDisabled: disabled)
        }
        return ManagedPlugin(key: key, name: key, vendor: "V", bundles: bundles)
    }

    @Test func aSavedPictureIsThereAfterARestart() throws {
        try LocalPictures(directory: folder).save(Data([1, 2, 3]), for: "pro-q|fabfilter")
        let again = LocalPictures(directory: folder)
        #expect(again.keys == ["pro-q|fabfilter"])
        #expect(try Data(contentsOf: again.url(for: "pro-q|fabfilter")) == Data([1, 2, 3]))
    }

    @Test func aKeyCannotLeaveTheFolder() {
        let pictures = LocalPictures(directory: folder)
        #expect(pictures.url(for: "../../evil/x").deletingLastPathComponent().standardizedFileURL.path
                == folder.standardizedFileURL.path)
    }

    @Test func differentKeysGetDifferentFiles() {
        let pictures = LocalPictures(directory: folder)
        #expect(pictures.url(for: "a/b") != pictures.url(for: "a|b"))
    }

    @Test func onlyPluginsWithAnAudioUnitCanBeCaptured() {
        let targets = LocalPictures.targets([plugin("au"), plugin("vst", formats: [.vst3])], skipping: [])
        #expect(targets.map(\.key) == ["au"])
    }

    @Test func aTurnedOffAudioUnitIsLeftOut() {
        #expect(LocalPictures.targets([plugin("off", disabled: true)], skipping: []).isEmpty)
    }

    @Test func pluginsWithAPictureAreLeftOut() {
        #expect(LocalPictures.targets([plugin("a"), plugin("b")], skipping: ["a"]).map(\.key) == ["b"])
    }
}

@Suite("Plugins that wouldn't open for a screenshot")
struct FailedShotsTests {
    private let dir: TempDir
    init() throws { dir = try TempDir() }

    private func plugin(_ key: String, version: String = "1") -> ManagedPlugin {
        let bundle = PluginBundle(url: URL(fileURLWithPath: "/p/\(key).component"), format: .au, vendor: "V", version: version,
                                  executable: nil, archs: [], quarantined: false, au: nil, nested: false)
        return ManagedPlugin(key: key, name: key.uppercased(), vendor: "V", bundles: [bundle])
    }

    @Test func aFailureIsRememberedAcrossLaunches() {
        LocalPictures(directory: dir.path("p")).noteFailures([plugin("a")])
        #expect(LocalPictures(directory: dir.path("p")).failedKeys(among: [plugin("a"), plugin("b")]) == ["a"])
    }

    @Test func anUpdateGetsAnotherTry() {
        let pictures = LocalPictures(directory: dir.path("p"))
        pictures.noteFailures([plugin("a", version: "1")])
        #expect(pictures.failedKeys(among: [plugin("a", version: "2")]).isEmpty)
    }

    @Test func failuresCanBeForgotten() {
        let pictures = LocalPictures(directory: dir.path("p"))
        pictures.noteFailures([plugin("a")])
        pictures.forgetFailures()
        #expect(pictures.failedKeys(among: [plugin("a")]).isEmpty)
    }

    @Test func aRemovedPluginLeavesNoPicture() throws {
        let pictures = LocalPictures(directory: dir.path("p"))
        try pictures.save(Data([1]), for: "a")
        pictures.remove("a")
        #expect(pictures.keys.isEmpty)
    }

    @Test @MainActor func theReportNamesWhatFailedAndNextTimeSkipsIt() async {
        let good = plugin("good"), bad = plugin("bad")
        let library = FLLibrary(demo: true, local: LocalPictures(directory: dir.path("p")),
                                shooter: { $0.key == "good" ? Data([1]) : nil })
        library.captureAll([good, bad])
        await wait { !library.busy }
        #expect(library.status == .captured(shots: 1, failed: ["BAD"]))
        #expect(library.failedKeys(among: [good, bad]) == ["bad"])
        #expect(library.localKeys == ["good"])
    }

    @Test @MainActor func aStopEndsAfterThePluginOpenNow() async {
        let library = FLLibrary(demo: true, local: LocalPictures(directory: dir.path("p")), shooter: { _ in
            Thread.sleep(forTimeInterval: 0.05)
            return Data([1])
        })
        library.captureAll((0..<50).map { plugin("p\($0)") })
        library.stopCapture()
        await wait { !library.busy }
        #expect(library.localKeys.count < 50)
    }
}

@Suite("Audio Unit codes")
struct FourCCTests {
    @Test func plainCodes() { #expect(PluginCapture.fourCC(0x4142_4344) == "ABCD") }

    /// Codes are Mac Roman: the same bytes read as UTF-8 give nothing Info.plist would match.
    @Test func codesBeyondASCII() { #expect(PluginCapture.fourCC(0xA961_6263) == "©abc") }
}

@Suite("Running a tool")
struct RunLoggedTests {
    @Test func theOutputComesBack() {
        #expect(PluginChecker.runLogged(URL(fileURLWithPath: "/bin/echo"), ["hello"], timeout: 5) == "hello\n")
    }

    @Test func aToolThatHangsIsKilled() {
        let start = Date()
        #expect(PluginChecker.runLogged(URL(fileURLWithPath: "/bin/sleep"), ["30"], timeout: 0.2) == nil)
        #expect(Date().timeIntervalSince(start) < 5)
    }
}

@Suite("Pictures load newest first")
struct PictureLoaderTests {
    @Test @MainActor func aCardThatLeftIsNotLoaded() async throws {
        let dir = try TempDir()
        let urls = (0..<4).map { dir.path("\($0).png") }
        let order = Recorder()
        let gate = DispatchSemaphore(value: 0)
        let loader = PictureLoader { url in
            if url == urls[0] { gate.wait() }
            order.add(url)
            return nil
        }
        var finished = 0
        _ = loader.load(urls[0]) { _ in finished += 1 }      // busy with this one
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = loader.load(urls[1]) { _ in finished += 1 }
        let gone = loader.load(urls[2]) { _ in finished += 1 }
        _ = loader.load(urls[3]) { _ in finished += 1 }
        loader.cancel(gone)
        gate.signal()
        await wait { finished == 3 }
        #expect(order.urls == [urls[0], urls[3], urls[1]])
    }

    private final class Recorder {
        private let lock = NSLock()
        private var seen: [URL] = []
        var urls: [URL] { lock.lock(); defer { lock.unlock() }; return seen }
        func add(_ url: URL) { lock.lock(); seen.append(url); lock.unlock() }
    }
}
