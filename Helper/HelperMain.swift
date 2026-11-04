import Foundation

/// PluginSorterHelper.app: the modes in HelperModes and nothing else. Any other arguments end here, so
/// this program can't turn into the app, whatever it's started with.
@main
enum HelperMain {
    static func main() {
        HelperModes.run(Array(CommandLine.arguments.dropFirst()))
        _exit(64)
    }
}
