import Foundation

enum Issue: Equatable, Codable {
    case noBinary
    case wrongArch([String])
    case rosetta
    case quarantined
    case notRegistered
    case validationFailed(String)
    case loadFailed(String)
    case timeout

    /// Problems that stop the plugin from loading; the rest are warnings.
    var isFatal: Bool {
        switch self {
        case .rosetta, .quarantined: return false
        default:                     return true
        }
    }
}

enum CheckState: Equatable {
    case unchecked
    case running
    case done([Issue])

    enum Level: Int, Comparable {
        case ok, warning, failed
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    var level: Level? {
        guard case .done(let issues) = self else { return nil }
        if issues.contains(where: \.isFatal) { return .failed }
        return issues.isEmpty ? .ok : .warning
    }
}

/// Checks that a plugin can actually be loaded.
///
/// Audio Units go through Apple's `auval`; VST, VST3 and CLAP are loaded in a separate copy of
/// the app (`--probe`) that looks up the plugin's entry point, so a crash only takes down the helper.
enum PluginChecker {
    static func check(_ bundle: PluginBundle) -> [Issue] {
        var issues: [Issue] = []
        if bundle.quarantined { issues.append(.quarantined) }
        guard bundle.executable != nil else { return issues + [.noBinary] }

        let host = PluginInventory.hostArch
        if !bundle.archs.isEmpty && !bundle.archs.contains(host) {
            if host == "arm64" && bundle.archs.contains("x86_64") {
                // Native hosts can't load it; Rosetta hosts can, so don't try to load it here
                return issues + [.rosetta]
            }
            return issues + [.wrongArch(bundle.archs)]
        }

        // Checking means running the plugin's code. Nobody has vouched for a download yet: that's the
        // user's call, and clearing the flag brings the check back
        if bundle.quarantined { return issues }

        if bundle.format == .au {
            // macOS only registers components that sit directly in Components
            guard !bundle.nested, let code = bundle.au else { return issues + [.notRegistered] }
            return issues + validateAU(code)
        }
        return issues + probe(bundle)
    }

    /// What's certain from the files alone, before any check runs: macOS ignores an AU in a subfolder.
    static func knownIssues(_ bundle: PluginBundle) -> [Issue]? {
        bundle.format == .au && bundle.nested ? [.notRegistered] : nil
    }

    // MARK: - Audio Units

    private static func validateAU(_ code: AUCode) -> [Issue] {
        let run = runLogged(URL(fileURLWithPath: "/usr/bin/auval"),
                            ["-v", code.type, code.subtype, code.manufacturer], timeout: 120)
        guard let output = run else { return [.timeout] }
        if output.contains("AU VALIDATION SUCCEEDED") { return [] }
        if output.contains("didn't find the component") { return [.notRegistered] }
        let reason = output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("FATAL ERROR") || $0.hasPrefix("ERROR") || $0.hasPrefix("Error") }
        return [.validationFailed(reason ?? "auval")]
    }

    // MARK: - VST, VST3, CLAP

    private static func probe(_ bundle: PluginBundle) -> [Issue] {
        guard let helper = Helper.process(["--probe", bundle.format.rawValue, bundle.url.path]),
              let output = runLogged(helper, timeout: 30, successMarker: "PROBE OK") else { return [.timeout] }
        if output.contains("PROBE OK") { return [] }
        let reason = output.split(separator: "\n").last.map(String.init) ?? ""
        return [.loadFailed(reason.isEmpty ? "crashed" : reason)]
    }

    // MARK: - Running tools

    /// Runs a tool with its output in a temp file (auval prints a lot), killing it after `timeout`.
    /// Returns nil on timeout unless the output already contains `successMarker`.
    static func runLogged(_ tool: URL, _ args: [String], timeout: TimeInterval,
                                  successMarker: String? = nil) -> String? {
        let process = Process()
        process.executableURL = tool
        process.arguments = args
        return runLogged(process, timeout: timeout, successMarker: successMarker)
    }

    /// The same for a process set up by the caller.
    static func runLogged(_ process: Process, timeout: TimeInterval, successMarker: String? = nil) -> String? {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: log) }
        guard let handle = try? FileHandle(forWritingTo: log) else { return nil }

        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardOutput = handle
        process.standardError = handle
        let ended = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in ended.signal() }
        guard (try? process.run()) != nil else { return nil }

        let timedOut = ended.wait(timeout: .now() + timeout) == .timedOut
        if timedOut { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        try? handle.close()

        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        if timedOut && !(successMarker.map(output.contains) ?? false) { return nil }
        return output
    }
}
