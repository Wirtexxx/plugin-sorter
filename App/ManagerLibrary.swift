import Foundation

enum ManagerStatus: Equatable {
    case idle
    case checked(ok: Int, warnings: Int, failed: Int)
    case trashed(Int)
    case cancelled
    case failed(String)
}

/// State of the Manager tab: every installed plugin, its check results and deletion.
final class ManagerLibrary: ObservableObject {
    @Published var plugins: [ManagedPlugin] = []
    @Published var results: [String: CheckState] = [:]
    @Published var query = ""
    @Published var onlyProblems = false
    @Published var expanded: Set<String> = []
    @Published var busy = false
    @Published var progress = 0.0
    @Published var current = ""
    @Published var status: ManagerStatus = .idle

    private let queue = DispatchQueue(label: "plugin-sorter.manager", qos: .userInitiated)
    private let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
    }

    var visible: [ManagedPlugin] {
        plugins.filter { plugin in
            let matches = query.isEmpty
                || plugin.name.localizedCaseInsensitiveContains(query)
                || plugin.vendor.localizedCaseInsensitiveContains(query)
            let problem = (level(of: plugin) ?? .ok) > .ok
            return matches && (!onlyProblems || problem)
        }
    }

    func state(of bundle: PluginBundle) -> CheckState { results[bundle.id] ?? .unchecked }

    /// The worst result among the plugin's formats, nil until checked.
    func level(of plugin: ManagedPlugin) -> CheckState.Level? {
        plugin.bundles.compactMap { state(of: $0).level }.max()
    }

    func count(_ level: CheckState.Level) -> Int {
        plugins.filter { self.level(of: $0) == level }.count
    }

    func scan() {
        guard !demo else { return }
        queue.async {
            let plugins = PluginInventory.scan()
            DispatchQueue.main.async {
                self.plugins = plugins
                // Forget results of bundles that are gone
                let ids = Set(plugins.flatMap { $0.bundles.map(\.id) })
                self.results = self.results.filter { ids.contains($0.key) }
            }
        }
    }

    func check(_ targets: [ManagedPlugin]) {
        let bundles = targets.flatMap(\.bundles)
        guard !busy, !bundles.isEmpty else { return }
        busy = true
        progress = 0
        bundles.forEach { results[$0.id] = .running }
        queue.async {
            for (n, bundle) in bundles.enumerated() {
                DispatchQueue.main.async {
                    self.current = "\(bundle.url.deletingPathExtension().lastPathComponent) · \(bundle.format.rawValue)"
                    self.progress = Double(n) / Double(bundles.count)
                }
                let issues = PluginChecker.check(bundle)
                DispatchQueue.main.async { self.results[bundle.id] = .done(issues) }
            }
            DispatchQueue.main.async {
                self.busy = false
                self.current = ""
                let checked = targets.compactMap { self.level(of: $0) }
                self.status = .checked(ok: checked.filter { $0 == .ok }.count,
                                       warnings: checked.filter { $0 == .warning }.count,
                                       failed: checked.filter { $0 == .failed }.count)
            }
        }
    }

    /// Moves the bundles to the Trash through the administrator dialog.
    func trash(_ bundles: [PluginBundle]) {
        guard !busy, !bundles.isEmpty else { return }
        busy = true
        queue.async {
            let result = Shell.runScript(["--trash"] + bundles.map(\.url.path), admin: true, env: Shell.ownerEnv)
            let trashed = result.output.split(separator: "\n").filter { $0.hasPrefix("trashed: ") }.count
            DispatchQueue.main.async {
                self.busy = false
                if result.succeeded {
                    self.status = .trashed(trashed)
                } else {
                    self.status = result.cancelled ? .cancelled : .failed(result.error)
                }
                self.scan()
            }
        }
    }
}
