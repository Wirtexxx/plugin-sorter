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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
