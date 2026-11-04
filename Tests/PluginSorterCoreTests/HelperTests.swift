import Foundation
import Testing
@testable import PluginSorterCore

/// The app starts copies of itself. On 3 November a build that didn't answer to the helper modes started
/// the whole app from every helper, and those started more, until the Mac had to be restarted.
@Suite("Starting helper processes")
struct HelperTests {
    private let binary = URL(fileURLWithPath: "/tmp/App.app/Contents/MacOS/App")

    @Test func aHelperKnowsItIsOne() {
        #expect(Helper.isHelper([Helper.marker: "1"]))
        #expect(!Helper.isHelper([:]))
    }

    @Test func theAppStartsAHelperMarkedAsOne() throws {
        let process = try #require(Helper.process(["--probe", "VST3", "/p"], environment: ["HOME": "/h"], executable: binary))
        #expect(process.executableURL == binary)
        #expect(process.arguments == ["--probe", "VST3", "/p"])
        #expect(process.environment?[Helper.marker] == "1")
        #expect(process.environment?["HOME"] == "/h")
    }

    @Test func aHelperNeverStartsAnother() {
        #expect(Helper.process(["--probe"], environment: [Helper.marker: "1"], executable: binary) == nil)
    }

    @Test func noExecutableNoHelper() {
        #expect(Helper.process(["--probe"], environment: [:], executable: nil) == nil)
    }

    @Test func everyHelperGoesThroughOnePlace() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("App")
        for file in try FileManager.default.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)
        where file.pathExtension == "swift" && file.lastPathComponent != "Helper.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("Bundle.main.executableURL"), "\(file.lastPathComponent) starts a helper on its own")
        }
    }

    @Test func aHelperOutlivesNobody() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("App")
        var limits = 0
        for file in try FileManager.default.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)
        where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            limits += text.components(separatedBy: "alarm(Helper.timeLimit)").count - 1
        }
        #expect(limits == 3)   // --probe, --tags, --capture
    }
}

@Suite("Which binary a helper is")
struct HelperBinaryTests {
    private let main = URL(fileURLWithPath: "/A/Plugin Sorter.app/Contents/MacOS/PluginSorter")
    private let helper = "/A/Plugin Sorter.app/Contents/Helpers/PluginSorterHelper.app/Contents/MacOS/PluginSorterHelper"

    @Test func theSeparateHelperIsPreferred() {
        #expect(Helper.executable(main: main, isExecutable: { $0 == helper })?.path == helper)
    }

    /// A build without the helper, like a run from the tests, keeps the old way: a copy of the app.
    @Test func withoutItTheAppItselfIsUsed() {
        #expect(Helper.executable(main: main, isExecutable: { _ in false }) == main)
    }

    @Test func noMainBinaryNoHelper() {
        #expect(Helper.executable(main: nil, isExecutable: { _ in true }) == nil)
    }

    @Test func modesAreKnown() {
        #expect(HelperModes.isHelperMode(["--probe", "VST3", "/p"]))
        #expect(HelperModes.isHelperMode(["--tags"]))
        #expect(HelperModes.isHelperMode(["--capture"]))
        #expect(!HelperModes.isHelperMode(["--other"]))
        #expect(!HelperModes.isHelperMode([]))
    }
}
