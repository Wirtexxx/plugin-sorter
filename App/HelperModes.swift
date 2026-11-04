import Foundation

/// The helper modes, shared by the separate helper and by the app when run the old way.
enum HelperModes {
    static func isHelperMode(_ arguments: [String]) -> Bool {
        ["--capture", "--probe", "--tags"].contains(arguments.first ?? "")
    }

    /// Runs the mode the arguments name and never comes back; returns when they name none.
    static func run(_ arguments: [String]) {
        switch arguments.first {
        case "--capture": CaptureHelper.run(arguments)
        case "--probe":   ProbeHelper.run(arguments)
        case "--tags":    TagsHelper.run(arguments)
        default:          return
        }
    }
}
