import Foundation

/// Runs the bundled scripts/sort-plugins.sh, the only code that touches /Library/Audio/Plug-Ins.
enum Shell {
    struct Result {
        let status: Int32
        let output: String
        let error: String

        var succeeded: Bool { status == 0 }
        /// The user closed the administrator password dialog: osascript ends its message with the code.
        /// Anywhere else it may be part of a file name.
        var cancelled: Bool { error.hasSuffix("(-128)") }
    }

    /// `do shell script` keeps no output of a command that fails, so the command always succeeds and
    /// says how the script ended on its last line.
    static let exitMarker = "__PLUGIN_SORT_EXIT:"

    private static let promptLock = NSLock()
    private static var promptText = "Plugin Sorter wants to change your plugin folders."

    /// The line in the administrator dialog, in the window's language. Without it the dialog names osascript.
    static var prompt: String {
        get { promptLock.lock(); defer { promptLock.unlock() }; return promptText }
        set { promptLock.lock(); defer { promptLock.unlock() }; promptText = newValue }
    }

    /// Worked out on every run: a lookup made while the app was being rebuilt must not stick.
    static var script: String { Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/sort-plugins.sh").path }

    /// Blocking. With `admin` the standard macOS administrator password dialog is shown.
    static func runScript(_ args: [String], admin: Bool, env: [String: String] = [:]) -> Result {
        let p = Process()
        if admin {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", adminAppleScript(args, env: env, prompt: prompt)]
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
        if admin { return adminResult(status: p.terminationStatus, stdout: stdout, stderr: stderr) }
        return Result(status: p.terminationStatus,
                      output: stdout,
                      error: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// What osascript gave back, with the script's own exit code when its marker is there.
    static func adminResult(status: Int32, stdout: String, stderr: String) -> Result {
        // do shell script returns line breaks as \r
        let text = stdout.replacingOccurrences(of: "\r", with: "\n")
        let failure = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let marker = text.range(of: exitMarker, options: .backwards),
              let code = Int32(text[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return Result(status: status == 0 ? -1 : status, output: text, error: failure)
        }
        let output = String(text[..<marker.lowerBound])
        return Result(status: code, output: output,
                      error: code == 0 ? "" : output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Environment the script needs when it runs as root through osascript, where SUDO_USER is unset.
    static var ownerEnv: [String: String] {
        ["PLUGIN_SORT_LOG_DIR": NSHomeDirectory(), "PLUGIN_SORT_OWNER": NSUserName(),
         "PLUGIN_SORT_KEEP_FILE": PluginFixes.keepFile.path]
    }

    static func adminAppleScript(_ args: [String], env: [String: String], prompt: String) -> String {
        let vars: [String] = env.map { key, value in "\(key)=\(quote(value))" }
        let argv: [String] = ([script] + args).map { quote($0) }
        let cmd = "env \(vars.joined(separator: " ")) /bin/bash \(argv.joined(separator: " ")) 2>&1; echo \(exitMarker)$?"
        return "do shell script \"" + literal(cmd) + "\" with prompt \"" + literal(prompt) + "\" with administrator privileges"
    }

    /// The inside of an AppleScript string.
    private static func literal(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
