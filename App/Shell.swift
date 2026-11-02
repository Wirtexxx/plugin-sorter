import Foundation

/// Runs the bundled scripts/sort-plugins.sh, the only code that touches /Library/Audio/Plug-Ins.
enum Shell {
    struct Result {
        let status: Int32
        let output: String
        let error: String

        var succeeded: Bool { status == 0 }
        /// The user closed the administrator password dialog.
        var cancelled: Bool { error.contains("-128") }
    }

    static let script = Bundle.main.path(forResource: "sort-plugins", ofType: "sh") ?? ""

    /// Blocking. With `admin` the standard macOS administrator password dialog is shown.
    static func runScript(_ args: [String], admin: Bool, env: [String: String] = [:]) -> Result {
        let p = Process()
        if admin {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", adminAppleScript(args, env: env)]
        } else {
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [script] + args
            p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch {
            return Result(status: -1, output: "", error: error.localizedDescription)
        }
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        // do shell script returns line breaks as \r
        return Result(status: p.terminationStatus,
                      output: stdout.replacingOccurrences(of: "\r", with: "\n"),
                      error: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Environment the script needs when it runs as root through osascript, where SUDO_USER is unset.
    static var ownerEnv: [String: String] {
        ["PLUGIN_SORT_LOG_DIR": NSHomeDirectory(), "PLUGIN_SORT_OWNER": NSUserName(),
         "PLUGIN_SORT_KEEP_FILE": PluginFixes.keepFile.path]
    }

    private static func adminAppleScript(_ args: [String], env: [String: String]) -> String {
        let vars: [String] = env.map { key, value in "\(key)=\(quote(value))" }
        let argv: [String] = ([script] + args).map { quote($0) }
        let cmd = "env \(vars.joined(separator: " ")) /bin/bash \(argv.joined(separator: " ")) 2>&1"
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"" + escaped + "\" with administrator privileges"
    }

    private static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
