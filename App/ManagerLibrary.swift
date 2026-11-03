import Foundation

enum ManagerStatus: Equatable {
    case idle
    case checked(ok: Int, warnings: Int, failed: Int)
    case trashed(Int)
    case fixed
    case cancelled
    case failed(String)
}

/// How far the background check has got.
struct CheckProgress: Equatable {
    let done: Int
    let total: Int
    let current: String
}

/// Every installed plugin, its check results and deletion. Plugins are checked automatically in the
/// background; results are saved, so only new and updated plugins are checked again.
final class ManagerLibrary: ObservableObject {
    @Published var plugins: [ManagedPlugin] = []
    @Published var results: [String: CheckState] = [:]
    @Published var busy = false
    @Published var status: ManagerStatus = .idle
    /// Bytes on disk per bundle (by path), filled in the background after each scan.
    @Published private(set) var sizes: [String: Int64] = [:]
    /// Developer folders with presets and libraries, per vendor. Shown, never deleted.
    @Published private(set) var vendorData: [String: [URL]] = [:]
    /// Sizes of those folders, measured only when a plugin's details are opened: they can hold
    /// hundreds of gigabytes of samples.
    @Published private(set) var folderSizes: [URL: Int64] = [:]
    private var measuring: Set<URL> = []
    /// Bumped by every scan so a slower, older measurement can't overwrite a newer one.
    private var sizeGeneration = 0

    /// Set while the background check runs.
    @Published private(set) var checking: CheckProgress?

    private let queue = DispatchQueue(label: "plugin-sorter.manager", qos: .userInitiated)
    private let checkQueue = DispatchQueue(label: "plugin-sorter.checks", qos: .utility)
    private let cache: CheckCache
    private let demo: Bool
    // Owned by the main thread
    private var queued: [PluginBundle] = []
    private var forgotten: Set<String> = []
    private var checkRunning = false
    private var batchDone = 0
    private var batchTotal = 0

    init(demo: Bool = false, cache: CheckCache = CheckCache()) {
        self.demo = demo
        self.cache = cache
    }

    func size(of bundle: PluginBundle) -> Int64? { sizes[bundle.id] }

    func size(of plugin: ManagedPlugin) -> Int64 { plugin.bundles.reduce(0) { $0 + (sizes[$1.id] ?? 0) } }

    /// Measures every bundle and finds developer data folders; runs off the main thread.
    private func computeSizes(for plugins: [ManagedPlugin]) {
        sizeGeneration += 1
        let generation = sizeGeneration
        DispatchQueue.global(qos: .utility).async {
            var sizes: [String: Int64] = [:]
            for bundle in plugins.flatMap(\.bundles) { sizes[bundle.id] = DiskUsage.size(of: bundle.url) }
            let folders = DiskUsage.dataFolders()
            var vendorData: [String: [URL]] = [:]
            for vendor in Set(plugins.map(\.vendor)) where !vendor.isEmpty {
                let found = DiskUsage.vendorFolders(for: vendor, among: folders)
                if !found.isEmpty { vendorData[vendor] = found }
            }
            DispatchQueue.main.async {
                guard generation == self.sizeGeneration else { return }
                self.sizes = sizes
                self.vendorData = vendorData
            }
        }
    }

    /// Measures developer folders the first time they're shown; later views use the cached size.
    func measure(_ folders: [URL]) {
        let todo = folders.filter { folderSizes[$0] == nil && !measuring.contains($0) }
        guard !todo.isEmpty else { return }
        measuring.formUnion(todo)
        DispatchQueue.global(qos: .utility).async {
            let measured = todo.map { ($0, DiskUsage.size(of: $0)) }
            DispatchQueue.main.async {
                for (url, size) in measured {
                    self.folderSizes[url] = size
                    self.measuring.remove(url)
                }
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
                if fix == .resetAUCache {
                    // Saved "not registered" results are out of date now that macOS has looked again
                    self.recheck(self.plugins.map { ManagedPlugin(key: $0.key, name: $0.name, vendor: $0.vendor,
                                                                  bundles: $0.bundles.filter { $0.format == .au }) })
                }
                self.scan {
                    if let key = plugin?.key, let updated = self.plugins.first(where: { $0.key == key }) {
                        self.recheck([updated])
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
                // Saved results first, so the list shows each plugin's state straight away
                var results: [String: CheckState] = [:]
                for bundle in plugins.flatMap(\.bundles) {
                    if self.results[bundle.id] == .running {
                        results[bundle.id] = .running
                    } else if let issues = self.cache.issues(for: bundle) ?? PluginChecker.knownIssues(bundle) {
                        results[bundle.id] = .done(issues)
                    }
                }
                self.results = results
                // Bundles still here (a cancelled Trash, a reinstall) may be checked again
                self.forgotten.subtract(plugins.flatMap { $0.bundles.map(\.id) })
                self.computeSizes(for: plugins)
                self.checkInBackground()
                completion?()
            }
        }
    }

    // MARK: - Background checks

    /// Queues every bundle that was never checked or changed since.
    func checkInBackground() {
        guard !demo else { return }
        let waiting = Set(queued.map(\.id))
        // Problems already certain from the files (an AU in a subfolder) need no check
        enqueue(CheckCache.pending(plugins.flatMap(\.bundles), cache: cache, forgotten: forgotten)
            .filter { !waiting.contains($0.id) && results[$0.id] != .running && PluginChecker.knownIssues($0) == nil })
    }

    /// Checks these plugins again even if a saved result exists.
    func recheck(_ targets: [ManagedPlugin]) {
        let waiting = Set(queued.map(\.id))
        enqueue(targets.flatMap(\.bundles).filter { !waiting.contains($0.id) && results[$0.id] != .running })
    }

    /// Forgets every saved result and checks everything again.
    func recheckAll() {
        cache.clear()
        queued.removeAll()
        results = results.filter { $0.value == .running }
        checkInBackground()
    }

    /// Takes bundles out of the queue, e.g. before they are moved to the Trash.
    func forget(_ bundles: [PluginBundle]) {
        let ids = Set(bundles.map(\.id))
        forgotten.formUnion(ids)
        queued.removeAll { ids.contains($0.id) }
    }

    private func enqueue(_ bundles: [PluginBundle]) {
        guard !bundles.isEmpty else { return }
        if !checkRunning {
            batchDone = 0
            batchTotal = 0
        }
        queued += bundles
        batchTotal += bundles.count
        if !checkRunning { checkNext() }
    }

    private func checkNext() {
        guard !queued.isEmpty else {
            checkRunning = false
            checking = nil
            return
        }
        checkRunning = true
        let bundle = queued.removeFirst()
        results[bundle.id] = .running
        checking = CheckProgress(done: batchDone, total: batchTotal,
                                 current: bundle.url.deletingPathExtension().lastPathComponent)
        checkQueue.async {
            let gone = !FileManager.default.fileExists(atPath: bundle.url.path)
            let issues = gone ? nil : PluginChecker.check(bundle)
            if let issues = issues { self.cache.store(issues, for: bundle) }
            DispatchQueue.main.async {
                self.batchDone += 1
                if let issues = issues, !self.forgotten.contains(bundle.id) {
                    self.results[bundle.id] = .done(issues)
                } else {
                    self.results[bundle.id] = nil
                }
                self.checkNext()
            }
        }
    }

    /// Moves the bundles to the Trash through the administrator dialog.
    func trash(_ bundles: [PluginBundle]) {
        guard !busy, !bundles.isEmpty else { return }
        forget(bundles)
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
