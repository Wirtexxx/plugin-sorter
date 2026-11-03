import Foundation

enum ManagerStatus: Equatable {
    case idle
    case checked(ok: Int, warnings: Int, failed: Int)
    case trashed(Int)
    case fixed
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
    @Published var sortBySize = false
    /// Bytes on disk per bundle (by path), filled in the background after each scan.
    @Published private(set) var sizes: [String: Int64] = [:]
    /// Developer folders with presets and libraries, per vendor. Shown, never deleted.
    @Published private(set) var vendorData: [String: [(url: URL, size: Int64)]] = [:]

    private let queue = DispatchQueue(label: "plugin-sorter.manager", qos: .userInitiated)
    private let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
    }

    var visible: [ManagedPlugin] {
        let filtered = plugins.filter { plugin in
            let matches = query.isEmpty
                || plugin.name.localizedCaseInsensitiveContains(query)
                || plugin.vendor.localizedCaseInsensitiveContains(query)
            let problem = (level(of: plugin) ?? .ok) > .ok
            return matches && (!onlyProblems || problem)
        }
        return sortBySize ? filtered.sorted { size(of: $0) > size(of: $1) } : filtered
    }

    func size(of bundle: PluginBundle) -> Int64? { sizes[bundle.id] }

    func size(of plugin: ManagedPlugin) -> Int64 { plugin.bundles.reduce(0) { $0 + (sizes[$1.id] ?? 0) } }

    var totalSize: Int64 { sizes.values.reduce(0, +) }

    /// Measures every bundle and finds developer data folders; runs off the main thread.
    private func computeSizes(for plugins: [ManagedPlugin]) {
        DispatchQueue.global(qos: .utility).async {
            var sizes: [String: Int64] = [:]
            for bundle in plugins.flatMap(\.bundles) { sizes[bundle.id] = DiskUsage.size(of: bundle.url) }
            var vendorData: [String: [(url: URL, size: Int64)]] = [:]
            for vendor in Set(plugins.map(\.vendor)) where !vendor.isEmpty {
                let folders = DiskUsage.vendorFolders(for: vendor).map { (url: $0, size: DiskUsage.size(of: $0)) }
                if !folders.isEmpty { vendorData[vendor] = folders }
            }
            DispatchQueue.main.async {
                self.sizes = sizes
                self.vendorData = vendorData
            }
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

    /// Repairs available for a checked bundle's problems.
    func fixes(for bundle: PluginBundle) -> [Fix] {
        guard case .done(let issues) = state(of: bundle), !issues.isEmpty else { return [] }
        return PluginFixes.fixes(for: bundle, issues: issues, installed: plugins.flatMap(\.bundles))
    }

    /// Runs a repair, then rescans and checks the plugin again so the result shows right away.
    func apply(_ fix: Fix, for plugin: ManagedPlugin?) {
        guard !busy else { return }
        busy = true
        queue.async {
            let args: [String]
            var admin = true
            switch fix {
            case .unquarantine(let url):      args = ["--unquarantine", url.path]
            case .relocate(let from, let to): args = ["--relocate", from.path, to.path]
            case .resetAUCache:               args = ["--reset-au"]; admin = false
            }
            let result = Shell.runScript(args, admin: admin, env: Shell.ownerEnv)
            let moved = result.output.contains("relocated: ")
            if moved, PluginFixes.isDependency(fix), case .relocate(_, let to) = fix {
                // Another plugin needs it exactly there: never sort it away again
                PluginFixes.keep(to.lastPathComponent)
            }
            DispatchQueue.main.async {
                self.busy = false
                if result.succeeded {
                    self.status = .fixed
                } else {
                    self.status = result.cancelled ? .cancelled : .failed(result.error)
                }
                guard result.succeeded else { return }
                self.scan {
                    if let key = plugin?.key, let updated = self.plugins.first(where: { $0.key == key }) {
                        self.check([updated])
                    }
                }
            }
        }
    }

    func scan(then completion: (() -> Void)? = nil) {
        guard !demo else { return }
        queue.async {
            let plugins = PluginInventory.scan()
            DispatchQueue.main.async {
                self.plugins = plugins
                // Forget results of bundles that are gone
                let ids = Set(plugins.flatMap { $0.bundles.map(\.id) })
                self.results = self.results.filter { ids.contains($0.key) }
                self.computeSizes(for: plugins)
                completion?()
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
