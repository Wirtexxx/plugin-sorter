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
        guard let executable = Bundle.main.executableURL else { return [] }
        guard let output = runLogged(executable, ["--probe", bundle.format.rawValue, bundle.url.path], timeout: 30,
                                     successMarker: "PROBE OK") else { return [.timeout] }
        if output.contains("PROBE OK") { return [] }
        let reason = output.split(separator: "\n").last.map(String.init) ?? ""
        return [.loadFailed(reason.isEmpty ? "crashed" : reason)]
    }

    /// Entry point for `--probe FORMAT PATH`. Prints "PROBE OK" or the reason it failed.
    static func runProbe(_ args: [String]) -> Never {
        guard args.count >= 3, let format = PluginFormat(rawValue: args[1]) else { _exit(1) }
        let url = URL(fileURLWithPath: args[2])
        func fail(_ message: String) -> Never {
            print(message)
            fflush(stdout)
            _exit(10)
        }

        guard let bundle = Bundle(url: url), let executable = bundle.executablePath else { fail("no executable") }
        guard let handle = dlopen(executable, RTLD_NOW | RTLD_LOCAL) else {
            fail(dlerror().map { String(cString: $0) } ?? "dlopen failed")
        }

        switch format {
        case .vst3:
            // Hosts call bundleEntry before asking for the factory
            if let entry = dlsym(handle, "bundleEntry"), let cfBundle = CFBundleCreate(nil, url as CFURL) {
                typealias BundleEntry = @convention(c) (CFBundle) -> Bool
                guard unsafeBitCast(entry, to: BundleEntry.self)(cfBundle) else { fail("bundleEntry returned false") }
            }
            guard let symbol = dlsym(handle, "GetPluginFactory") else { fail("GetPluginFactory not found") }
            typealias GetFactory = @convention(c) () -> UnsafeMutableRawPointer?
            guard unsafeBitCast(symbol, to: GetFactory.self)() != nil else { fail("no plugin factory") }
        case .vst:
            guard dlsym(handle, "VSTPluginMain") != nil || dlsym(handle, "main_macho") != nil else {
                fail("VSTPluginMain not found")
            }
        case .clap:
            guard dlsym(handle, "clap_entry") != nil else { fail("clap_entry not found") }
        case .au:
            break
        }
        print("PROBE OK")
        fflush(stdout)
        // _exit skips plugin destructors, some of which abort outside a real host
        _exit(0)
    }

    // MARK: - Running tools

    /// Runs a tool with its output in a temp file (auval prints a lot), killing it after `timeout`.
    /// Returns nil on timeout unless the output already contains `successMarker`.
    static func runLogged(_ tool: URL, _ args: [String], timeout: TimeInterval,
                                  successMarker: String? = nil) -> String? {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: log) }
        guard let handle = try? FileHandle(forWritingTo: log) else { return nil }

        let process = Process()
        process.executableURL = tool
        process.arguments = args
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardOutput = handle
        process.standardError = handle
        guard (try? process.run()) != nil else { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(100_000) }
        let timedOut = process.isRunning
        if timedOut { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        try? handle.close()

        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        if timedOut && !(successMarker.map(output.contains) ?? false) { return nil }
        return output
    }
}
