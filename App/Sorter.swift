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
    enum Kind { case waves, kept, unknown, exists, restored, skipped, failed, other }
    let id = UUID()
    let kind: Kind
    let text: String
}

enum Status: Equatable {
    case idle, noFormats, undone, cancelled
    case willMove(Int)
    case moved(Int)
    /// Some of the plugins stayed where they were.
    case partlyMoved(moved: Int, failed: Int)
    /// Some moves couldn't be taken back; the log is kept, so undoing again finishes the job.
    case undoIncomplete(failed: Int)
    case failed(String)
}

/// Runs scripts/sort-plugins.sh and turns its output into view state.
final class Sorter: ObservableObject {
    @Published var vst3 = true
    @Published var vst = true
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
    private let runner: Runner
    // Owned by the main thread
    private var inFlight = 0 { didSet { running = inFlight > 0 } }
    /// A run that moves plugins: there is one at a time, and nothing looks at the folders meanwhile.
    private var changing = false
    /// Bumped by every preview and every move, so only the newest preview gets to speak.
    private var previewGeneration = 0

    typealias Runner = (_ args: [String], _ admin: Bool, _ env: [String: String]) -> Shell.Result

    init(demo: Bool = false, runner: @escaping Runner = { Shell.runScript($0, admin: $1, env: $2) }) {
        self.demo = demo
        self.runner = runner
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
        guard !changing else { return }
        guard !formats.isEmpty else { moves = []; notes = []; status = .noFormats; previewed = true; return }
        previewGeneration += 1
        let generation = previewGeneration
        run([], admin: false) { output in
            guard generation == self.previewGeneration else { return }
            let result = Self.parse(output)
            self.applied = false
            self.previewed = true
            self.moves = result.moves
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
            self.status = result.failed > 0 ? .partlyMoved(moved: result.count, failed: result.failed) : .moved(result.count)
        }
    }

    func undo() {
        guard let log = latestLog else { return }
        run(["--undo", log], admin: true) { output in
            let result = Self.parse(output)
            self.notes = result.notes
            self.status = result.failed > 0 ? .undoIncomplete(failed: result.failed) : .undone
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

    static func parse(_ output: String) -> (moves: [Move], notes: [Note], count: Int, failed: Int) {
        var format = ""
        var moves: [Move] = []
        var notes: [Note] = []
        var count = 0
        let number = { (line: String) in Int(String(line.drop { !$0.isNumber }.prefix { $0.isNumber })) ?? 0 }
        let prefixes: [(String, Note.Kind)] = [
            ("skip (Waves): ", .waves), ("keep: ", .kept), ("unknown vendor: ", .unknown), ("exists: ", .exists),
            ("restored: ", .restored), ("skip: ", .skipped), ("failed: ", .failed),
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
            if line.hasPrefix("Would move: ") || line.hasPrefix("Moved: ") {
                count = number(line)
            } else if line.hasPrefix("nested AU: ") {
                continue
            } else if line.hasSuffix("/"), let r = line.range(of: " -> ") {
                let file = String(line[..<r.lowerBound])
                moves.append(Move(plugin: (file as NSString).deletingPathExtension,
                                  vendor: String(line[r.upperBound...].dropLast()),
                                  format: format == "Components" ? "AU" : format))
            } else {
                notes.append(Note(kind: .other, text: line))
            }
        }
        return (moves, notes, count, notes.filter { $0.kind == .failed }.count)
    }

    // MARK: - Running the script

    private func run(_ args: [String], admin: Bool, done: @escaping (String) -> Void) {
        if admin {
            guard !changing else { return }
            changing = true
            previewGeneration += 1   // what a preview running now sees is about to change
        }
        inFlight += 1
        let env = self.env
        let runner = self.runner
        DispatchQueue.global(qos: .userInitiated).async {
            let result = runner(args, admin, env)
            DispatchQueue.main.async {
                self.inFlight -= 1
                if admin { self.changing = false }
                if result.succeeded {
                    done(result.output)
                } else if result.cancelled {
                    self.status = .cancelled
                } else if Self.parse(result.output).failed > 0 {
                    // Part of it went through: the caller says how much
                    done(result.output)
                } else {
                    self.status = .failed(result.error)
                }
                self.refreshLatestLog()
            }
        }
    }
}
