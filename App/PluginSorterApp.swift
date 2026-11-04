import SwiftUI
import AppKit

@main
enum Entry {
    static func main() {
        // Bundles with PluginSorterHelper.app never come here: this is for builds that run a copy of the app
        HelperModes.run(Array(CommandLine.arguments.dropFirst()))
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
