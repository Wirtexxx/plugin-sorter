import Foundation

struct Move: Identifiable {
    let id = UUID()
    let plugin: String
    let vendor: String
    let format: String
}

struct VendorGroup: Identifiable {
    var id: String { vendor }
    let vendor: String
    let items: [Move]
}

struct Note: Identifiable {
    enum Kind { case waves, unknown, exists, restored, skipped, other }
    let id = UUID()
    let kind: Kind
    let text: String
}

enum Status: Equatable {
    case idle, noFormats, undone, cancelled
    case willMove(Int)
    case moved(Int)
    case auRestored(Int)
    case failed(String)
}

/// Runs scripts/sort-plugins.sh and turns its output into view state.
final class Sorter: ObservableObject {
    @Published var vst3 = true
    @Published var vst = true
    /// Audio Units left in subfolders by versions before 1.1, which macOS can't load.
    @Published var nestedAU = 0
    @Published var moves: [Move] = []
    @Published var notes: [Note] = []
    @Published var status: Status = .idle
    @Published var running = false
    @Published var applied = false
    @Published var latestLog: String?

    private let script = Bundle.main.path(forResource: "sort-plugins", ofType: "sh") ?? ""
    private let logDir = NSHomeDirectory()
    private let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
    }

    var formats: String {
        [vst3 ? "VST3" : nil, vst ? "VST" : nil]
            .compactMap { $0 }.joined(separator: " ")
    }

    var groups: [VendorGroup] {
        Dictionary(grouping: moves, by: \.vendor)
            .map { VendorGroup(vendor: $0.key, items: $0.value) }
            .sorted { $0.vendor.localizedCaseInsensitiveCompare($1.vendor) == .orderedAscending }
    }

    private var env: [String: String] {
        ["PLUGIN_SORT_FORMATS": formats,
         "PLUGIN_SORT_LOG_DIR": logDir,
         "PLUGIN_SORT_OWNER": NSUserName()]
    }

    func preview(keepStatus: Bool = false) {
        guard !demo else { return }
        guard !formats.isEmpty else { moves = []; notes = []; status = .noFormats; return }
        run([], admin: false) { output in
            let result = Self.parse(output)
            self.applied = false
            self.moves = result.moves
            self.nestedAU = result.nestedAU
            if !keepStatus {
                self.notes = result.notes
                self.status = .willMove(result.count)
            }
        }
    }

    func apply() {
        run(["--apply"], admin: true) { output in
            let result = Self.parse(output)
            self.applied = true
            self.moves = result.moves
            self.notes = result.notes
            self.status = .moved(result.count)
        }
    }

    func undo() {
        guard let log = latestLog else { return }
        run(["--undo", log], admin: true) { output in
            self.notes = Self.parse(output).notes
            self.status = .undone
            self.preview(keepStatus: true)
        }
    }

    func restoreAU() {
        run(["--restore-au"], admin: true) { output in
            let result = Self.parse(output)
            self.notes = result.notes
            self.status = .auRestored(result.count)
            self.preview(keepStatus: true)
        }
    }

    func refreshLatestLog() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: logDir)) ?? []
        latestLog = files
            .filter { $0.hasPrefix("plugin-sort-") && $0.hasSuffix(".log") }
            .sorted().last
            .map { logDir + "/" + $0 }
    }

    // MARK: - Output parsing

    static func parse(_ output: String) -> (moves: [Move], notes: [Note], count: Int, nestedAU: Int) {
        var format = ""
        var moves: [Move] = []
        var notes: [Note] = []
        var count = 0
        var nestedAU = 0
        let number = { (line: String) in Int(String(line.drop { !$0.isNumber }.prefix { $0.isNumber })) ?? 0 }
        let prefixes: [(String, Note.Kind)] = [
            ("skip (Waves): ", .waves), ("unknown vendor: ", .unknown), ("exists: ", .exists),
            ("restored: ", .restored), ("skip: ", .skipped),
        ]

        lines: for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("Log: ") { continue }
            if line.hasPrefix("== ") {
                format = String(line.dropFirst(3))
                continue
            }
            for (prefix, kind) in prefixes where line.hasPrefix(prefix) {
                notes.append(Note(kind: kind, text: String(line.dropFirst(prefix.count))))
                continue lines
            }
            if line.hasPrefix("Would move: ") || line.hasPrefix("Moved: ") || line.hasPrefix("Restored AU: ") {
                count = number(line)
            } else if line.hasPrefix("nested AU: ") {
                nestedAU = number(line)
            } else if line.hasSuffix("/"), let r = line.range(of: " -> ") {
                let file = String(line[..<r.lowerBound])
                moves.append(Move(plugin: (file as NSString).deletingPathExtension,
                                  vendor: String(line[r.upperBound...].dropLast()),
                                  format: format == "Components" ? "AU" : format))
            } else {
                notes.append(Note(kind: .other, text: line))
            }
        }
        return (moves, notes, count, nestedAU)
    }

    // MARK: - Running the script

    private func run(_ args: [String], admin: Bool, done: @escaping (String) -> Void) {
        running = true
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            if admin {
                // Shows the standard macOS administrator password dialog
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", self.adminAppleScript(args)]
            } else {
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = [self.script] + args
                p.environment = ProcessInfo.processInfo.environment.merging(self.env) { $1 }
            }
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            do { try p.run() } catch {
                DispatchQueue.main.async {
                    self.running = false
                    self.status = .failed(error.localizedDescription)
                }
                return
            }
            let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()

            DispatchQueue.main.async {
                self.running = false
                if p.terminationStatus == 0 {
                    // do shell script returns line breaks as \r
                    done(stdout.replacingOccurrences(of: "\r", with: "\n"))
                } else if stderr.contains("-128") {
                    self.status = .cancelled
                } else {
                    self.status = .failed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                self.refreshLatestLog()
            }
        }
    }

    private func adminAppleScript(_ args: [String]) -> String {
        let vars: [String] = env.map { key, value in key + "=" + Self.quote(value) }
        let argv: [String] = ([script] + args).map { Self.quote($0) }
        let cmd: String = "env " + vars.joined(separator: " ") + " /bin/bash " + argv.joined(separator: " ") + " 2>&1"
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"" + escaped + "\" with administrator privileges"
    }

    private static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
