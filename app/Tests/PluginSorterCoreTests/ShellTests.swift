import Foundation
import Testing
@testable import PluginSorterCore

/// `do shell script` throws away stdout when the command fails, so the command always ends with a marker
/// that carries the script's own exit code.
@Suite("Reading what osascript gives back")
struct ShellTests {
    @Test func theScriptsExitCodeAndOutputSurviveAFailure() {
        let result = Shell.adminResult(status: 0, stdout: "trashed: A.vst3\rfailed: B.vst3\r__PLUGIN_SORT_EXIT:1", stderr: "")
        #expect(result.status == 1)
        #expect(!result.succeeded)
        #expect(result.output == "trashed: A.vst3\nfailed: B.vst3\n")
        #expect(result.error == "trashed: A.vst3\nfailed: B.vst3")
    }

    @Test func aGoodRunHasNoError() {
        let result = Shell.adminResult(status: 0, stdout: "Moved: 2\r__PLUGIN_SORT_EXIT:0", stderr: "")
        #expect(result.succeeded)
        #expect(result.output == "Moved: 2\n")
        #expect(result.error.isEmpty)
    }

    @Test func closingThePasswordDialogIsACancel() {
        let result = Shell.adminResult(status: 1, stdout: "", stderr: "0:97: execution error: User canceled. (-128)\n")
        #expect(result.cancelled)
    }

    @Test func aFileNameWithTheCancelCodeIsNotACancel() {
        let result = Shell.adminResult(status: 0, stdout: "skip: /x/Foo-128.vst3\r__PLUGIN_SORT_EXIT:1", stderr: "")
        #expect(!result.cancelled)
        #expect(!Shell.Result(status: 1, output: "", error: "execution error: skip: /x/Foo-128.vst3 (1)").cancelled)
    }

    @Test func noMarkerIsAFailure() {
        let result = Shell.adminResult(status: 1, stdout: "", stderr: "something broke")
        #expect(!result.succeeded)
        #expect(result.error == "something broke")
    }

    @Test func theCommandReportsItsExitCodeAndNamesTheApp() {
        let text = Shell.adminAppleScript(["--apply"], env: ["A": "b"], prompt: "Plugin Sorter")
        #expect(text.contains("__PLUGIN_SORT_EXIT:"))
        #expect(text.contains("with prompt \"Plugin Sorter\""))
        #expect(text.hasSuffix("with administrator privileges"))
    }

    @Test func thePromptCannotBreakOutOfTheScript() {
        let text = Shell.adminAppleScript([], env: [:], prompt: "a\"b\\c")
        #expect(text.contains("with prompt \"a\\\"b\\\\c\""))
    }
}
