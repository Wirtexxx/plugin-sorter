import Foundation

/// The only place that starts a helper: a process that loads a plugin (`--probe`, `--tags`, `--capture`),
/// so that a plugin that crashes or hangs takes down the helper and nothing else. It is the small
/// PluginSorterHelper.app inside the bundle, which has no window of its own to open and, being another
/// program to the Keychain, no way to the saved licenses. Without it, a copy of the app does the job.
///
/// A helper carries `marker` in its environment and can't start another. Whatever the binary does with
/// the arguments, the chain ends there: on 3 November a build without the helper modes started the whole
/// app from every helper, and each of those started more.
enum Helper {
    static let marker = "PLUGIN_SORTER_HELPER"

    /// Seconds after which a helper ends itself, set with alarm(): it must also go when the app that
    /// would kill it is gone. Above the longest time the app waits for one.
    static let timeLimit: UInt32 = 35

    static func isHelper(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[marker] != nil
    }

    /// The separate helper when the bundle has one, else the app itself.
    static func executable(main: URL? = Bundle.main.executableURL,
                           isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> URL? {
        guard let main = main else { return nil }
        let helper = main.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Helpers/PluginSorterHelper.app/Contents/MacOS/PluginSorterHelper")
        return isExecutable(helper.path) ? helper : main
    }

    /// A helper ready to run, or nil inside a helper.
    static func process(_ arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment,
                        executable: URL? = Helper.executable()) -> Process? {
        guard !isHelper(environment), let executable = executable else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment.merging([marker: "1"]) { $1 }
        return process
    }
}
