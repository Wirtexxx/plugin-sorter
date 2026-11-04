import SwiftUI
import AppKit

@main
enum Entry {
    static func main() {
        // The FL tab launches the app again in this mode to screenshot plugins in isolation
        if CommandLine.arguments.dropFirst().first == "--capture" {
            PluginCapture.runHelper(Array(CommandLine.arguments.dropFirst()))
        }
        // The Manager tab test-loads VST, VST3 and CLAP plugins in this mode
        if CommandLine.arguments.dropFirst().first == "--probe" {
            PluginChecker.runProbe(Array(CommandLine.arguments.dropFirst()))
        }
        // The FL tab reads the categories VST3 and CLAP plugins report about themselves in this mode
        if CommandLine.arguments.dropFirst().first == "--tags" {
            PluginTags.runHelper(Array(CommandLine.arguments.dropFirst()))
        }
        // Marked as a helper but no mode to run: the window must never open from here
        if Helper.isHelper() { _exit(64) }
        PluginSorterApp.main()
    }
}

struct PluginSorterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 860, minHeight: 620)
        }
        .commands { CommandGroup(replacing: .newItem) {} }

        // Plugin Sorter → Settings… (⌘,)
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
