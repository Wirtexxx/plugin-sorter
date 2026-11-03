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
    enum Kind { case waves, kept, unknown, exists, restored, skipped, other }
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
    /// A preview has finished, so `moves` says what is really left.
    @Published private var previewed = false
    var loaded: Bool { demo || previewed }

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
         "PLUGIN_SORT_OWNER": NSUserName(),
         "PLUGIN_SORT_KEEP_FILE": PluginFixes.keepFile.path]
    }

    func preview(keepStatus: Bool = false) {
        guard !demo else { return }
        guard !formats.isEmpty else { moves = []; notes = []; status = .noFormats; previewed = true; return }
        run([], admin: false) { output in
            let result = Self.parse(output)
            self.applied = false
            self.previewed = true
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
            ("skip (Waves): ", .waves), ("keep: ", .kept), ("unknown vendor: ", .unknown), ("exists: ", .exists),
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
        let env = self.env
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Shell.runScript(args, admin: admin, env: env)
            DispatchQueue.main.async {
                self.running = false
                if result.succeeded {
                    done(result.output)
                } else if result.cancelled {
                    self.status = .cancelled
                } else {
                    self.status = .failed(result.error)
                }
                self.refreshLatestLog()
            }
        }
    }
}
