import Foundation

enum ManagerStatus: Equatable {
    case idle
    case checked(ok: Int, warnings: Int, failed: Int)
    case trashed(Int)
    /// A job that went through in part: how much, and what stayed.
    case partly(done: Int, failed: [String])
    /// The list was saved to a file: how many plugins it has.
    case exported(Int)
    /// Plugins turned off (`disabled`) or on again.
    case toggled(disabled: Bool, count: Int)
    case fixed
    /// The star of a plugin FL has not scanned yet.
    case notSeenByFL
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
    private var measuredBundles: [String: MeasuredBundle] = [:]
    /// Bumped by every scan so a slower, older measurement can't overwrite a newer one.
    private var sizeGeneration = 0

    /// Set while the background check runs.
    @Published private(set) var checking: CheckProgress?

    private let queue = DispatchQueue(label: "plugin-sorter.manager", qos: .userInitiated)
    private let checkQueue = DispatchQueue(label: "plugin-sorter.checks", qos: .utility)
    private let cache: CheckCache
    private let demo: Bool
    private let runner: Sorter.Runner
    private let inventory: () -> [ManagedPlugin]
    private let checker: (PluginBundle) -> [Issue]
    private let trasher: (URL) throws -> Void
    private let userRoot: URL
    // Owned by the main thread
    private var queued: [PluginBundle] = []
    private var forgotten: Set<String> = []
    private var checkRunning = false
    private var batchDone = 0
    private var batchTotal = 0
    private var afterScan: [() -> Void] = []
    private let afterScanLock = NSLock()
    private let scans = ScanGate()

    init(demo: Bool = false, cache: CheckCache = CheckCache(),
         runner: @escaping Sorter.Runner = { Shell.runScript($0, admin: $1, env: $2) },
         inventory: @escaping () -> [ManagedPlugin] = PluginInventory.scanAll,
         checker: @escaping (PluginBundle) -> [Issue] = PluginChecker.check,
         trasher: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
         userRoot: URL = PluginInventory.userRoot) {
        self.demo = demo
        self.cache = cache
        self.runner = runner
        self.inventory = inventory
        self.checker = checker
        self.trasher = trasher
        self.userRoot = userRoot
    }

    func size(of bundle: PluginBundle) -> Int64? { sizes[bundle.id] }

    func size(of plugin: ManagedPlugin) -> Int64 { plugin.bundles.reduce(0) { $0 + (sizes[$1.id] ?? 0) } }

    /// Measures every bundle and finds developer data folders; runs off the main thread.
    private func computeSizes(for plugins: [ManagedPlugin]) {
        sizeGeneration += 1
        let generation = sizeGeneration
        let known = measuredBundles
        DispatchQueue.global(qos: .utility).async {
            let measured = DiskUsage.sizes(of: plugins.flatMap(\.bundles), known: known)
            let sizes = measured.mapValues(\.size)
            let folders = DiskUsage.dataFolders()
            var vendorData: [String: [URL]] = [:]
            for vendor in Set(plugins.map(\.vendor)) where !vendor.isEmpty {
                let found = DiskUsage.vendorFolders(for: vendor, among: folders)
                if !found.isEmpty { vendorData[vendor] = found }
            }
            DispatchQueue.main.async {
                guard generation == self.sizeGeneration else { return }
                self.measuredBundles = measured
                // Nothing changed is the usual case: no reason to redraw the window
                if sizes != self.sizes { self.sizes = sizes }
                if vendorData != self.vendorData { self.vendorData = vendorData }
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
        plugin.activeBundles.compactMap { state(of: $0).level }.max()
    }

    func count(_ level: CheckState.Level) -> Int {
        plugins.filter { self.level(of: $0) == level }.count
    }

    /// Repairs available for a checked bundle's problems.
    func fixes(for bundle: PluginBundle) -> [Fix] {
        guard case .done(let issues) = state(of: bundle), !issues.isEmpty else { return [] }
        return PluginFixes.fixes(for: bundle, issues: issues, installed: plugins.flatMap(\.activeBundles))
    }

    /// Runs a repair, then rescans and checks the plugin again so the result shows right away.
    func apply(_ fix: Fix, for plugin: ManagedPlugin?) {
        guard !busy else { return }
        busy = true
        queue.async {
            let result = self.run(fix)
            let moved = result.output.contains("relocated: ")
            var keepError: Error?
            if moved, PluginFixes.isDependency(fix), case .relocate(_, let to) = fix {
                // Another plugin needs it exactly there: never sort it away again
                do { try PluginFixes.keep(to.lastPathComponent) } catch { keepError = error }
            }
            DispatchQueue.main.async {
                self.busy = false
                if let error = keepError {
                    self.status = .failed(error.localizedDescription)
                } else if result.succeeded {
                    self.status = .fixed
                } else {
                    self.status = result.cancelled ? .cancelled : .failed(result.error)
                }
                guard result.succeeded else { return }
                if fix == .resetAUCache {
                    // Saved "not registered" results are out of date now that macOS has looked again
                    self.recheck(self.plugins.map { ManagedPlugin(key: $0.key, name: $0.name, vendor: $0.vendor,
                                                                  bundles: $0.activeBundles.filter { $0.format == .au }) })
                }
                self.scan {
                    if let key = plugin?.key, let updated = self.plugins.first(where: { $0.key == key }) {
                        self.recheck([updated])
                    }
                }
            }
        }
    }

    /// Runs a repair: the script for the shared folders, directly for the user's own.
    private func run(_ fix: Fix) -> Shell.Result {
        let own = userRoot.path + "/"
        do {
            switch fix {
            case .unquarantine(let url) where url.path.hasPrefix(own):
                try UserPlugins.unquarantine(url)
                return Shell.Result(status: 0, output: "", error: "")
            case .relocate(let from, let to) where from.path.hasPrefix(own):
                try UserPlugins.relocate(from: from, to: to)
                return Shell.Result(status: 0, output: "relocated: \(from.lastPathComponent)\n", error: "")
            case .unquarantine(let url):      return runner(["--unquarantine", url.path], true, Shell.ownerEnv)
            case .relocate(let from, let to): return runner(["--relocate", from.path, to.path], true, Shell.ownerEnv)
            case .resetAUCache:               return runner(["--reset-au"], false, Shell.ownerEnv)
            }
        } catch {
            return Shell.Result(status: 1, output: "", error: error.localizedDescription)
        }
    }

    func scan(then completion: (() -> Void)? = nil) {
        guard !demo else { return }
        if let completion = completion {
            afterScanLock.lock()
            afterScan.append(completion)
            afterScanLock.unlock()
        }
        guard scans.request() else { return }
        queue.async {
            self.scans.started()
            // Taken as this scan starts: a completion must see what its caller just changed
            self.afterScanLock.lock()
            let finished = self.afterScan
            self.afterScan = []
            self.afterScanLock.unlock()
            let plugins = self.inventory()
            let saved = self.cache.saved(for: plugins.flatMap(\.bundles))
            DispatchQueue.main.async {
                self.plugins = plugins
                // Saved results first, so the list shows each plugin's state straight away
                var results: [String: CheckState] = [:]
                for bundle in plugins.flatMap(\.bundles) {
                    if self.results[bundle.id] == .running {
                        results[bundle.id] = .running
                    } else if let issues = saved[bundle.id] ?? PluginChecker.knownIssues(bundle) {
                        results[bundle.id] = .done(issues)
                    }
                }
                self.results = results
                // Bundles still here (a cancelled Trash, a reinstall) may be checked again
                self.forgotten.subtract(plugins.flatMap { $0.bundles.map(\.id) })
                self.computeSizes(for: plugins)
                self.checkInBackground(saved: saved)
                finished.forEach { $0() }
            }
        }
    }

    // MARK: - Background checks

    /// Queues every bundle that was never checked or changed since.
    func checkInBackground(saved: [String: [Issue]]) {
        guard !demo else { return }
        let waiting = Set(queued.map(\.id))
        // Problems already certain from the files (an AU in a subfolder) need no check
        enqueue(CheckCache.pending(plugins.flatMap(\.activeBundles), saved: saved, forgotten: forgotten)
            .filter { !waiting.contains($0.id) && results[$0.id] != .running && PluginChecker.knownIssues($0) == nil })
    }

    /// Checks these plugins again even if a saved result exists.
    func recheck(_ targets: [ManagedPlugin]) {
        let waiting = Set(queued.map(\.id))
        enqueue(targets.flatMap(\.activeBundles).filter { !waiting.contains($0.id) && results[$0.id] != .running })
    }

    /// Forgets every saved result and checks everything again.
    func recheckAll() {
        cache.clear()
        queued.removeAll()
        results = results.filter { $0.value == .running }
        checkInBackground(saved: [:])
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
            let issues = gone ? nil : self.checker(bundle)
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

    /// Turns a plugin off, moving its files to Disabled/ where no host looks, or on again. Nothing is deleted.
    func setDisabled(_ plugin: ManagedPlugin, _ disabled: Bool) {
        let targets = disabled ? plugin.activeBundles : plugin.bundles.filter(\.isDisabled)
        guard !busy, !targets.isEmpty else { return }
        forget(targets)
        busy = true
        let own = targets.filter(\.isUserLevel)
        let shared = targets.filter { !$0.isUserLevel }
        let userRoot = self.userRoot
        queue.async {
            var done = 0
            var failed: [String] = []
            for bundle in own {
                do {
                    try UserPlugins.setDisabled(bundle, disabled, root: userRoot)
                    done += 1
                } catch {
                    failed.append(bundle.displayPath)
                }
            }
            var result: Shell.Result?
            if !shared.isEmpty {
                let run = self.runner([disabled ? "--disable" : "--enable"] + shared.map(\.url.path), true, Shell.ownerEnv)
                done += Self.lines(run, disabled ? "disabled: " : "enabled: ").count
                failed += Self.failures(run)
                result = run
            }
            if own.contains(where: { $0.format == .au }) { _ = self.runner(["--reset-au"], false, Shell.ownerEnv) }
            let status = Self.outcome(done: done, failed: failed, result: result, success: .toggled(disabled: disabled, count: done))
            DispatchQueue.main.async {
                self.busy = false
                self.status = status
                self.scan()
            }
        }
    }

    /// Removes a plugin with what it left behind, all after one administrator password: its files, the
    /// chosen leftovers in the shared folders and the installer receipts that nothing else needs.
    /// Leftovers in the user's own folders go to the Trash afterwards, without the dialog, and only when
    /// the plugin's files are gone: otherwise it would stay installed without its settings.
    func uninstall(_ plugin: ManagedPlugin, leftovers: [Leftover], receipts: [Receipt]) {
        guard !busy else { return }
        forget(plugin.bundles)
        busy = true
        let home = NSHomeDirectory() + "/"
        let ownLeftovers = leftovers.filter { $0.url.path.hasPrefix(home) }
        let sharedLeftovers = leftovers.filter { !$0.url.path.hasPrefix(home) }
        let ownBundles = plugin.bundles.filter(\.isUserLevel)
        let sharedBundles = plugin.bundles.filter { !$0.isUserLevel }
        var args: [String] = []
        if !sharedBundles.isEmpty { args += ["--trash"] + sharedBundles.map(\.url.path) }
        if !sharedLeftovers.isEmpty { args += ["--trash-data"] + sharedLeftovers.map(\.url.path) }
        if !receipts.isEmpty { args += ["--forget-receipt"] + receipts.map(\.id) }
        queue.async {
            var done = 0
            var failed: [String] = []
            for bundle in ownBundles { self.trashOwn(bundle.url, &done, &failed) }
            var result: Shell.Result?
            if !args.isEmpty {
                let run = self.runner(args, true, Shell.ownerEnv)
                done += Self.lines(run, "trashed: ").count + Self.lines(run, "trashed-data: ").count
                failed += Self.failures(run)
                Uninstall.dropFromCache(Set(Self.lines(run, "forgot: ")))
                result = run
            }
            if failed.isEmpty, result?.succeeded ?? true {
                for item in ownLeftovers { self.trashOwn(item.url, &done, &failed) }
            }
            let status = Self.outcome(done: done, failed: failed, result: result, success: .trashed(done))
            DispatchQueue.main.async {
                self.busy = false
                self.status = status
                self.scan()
            }
        }
    }

    /// Moves the bundles to the Trash, through the administrator dialog when they need it.
    func trash(_ bundles: [PluginBundle]) {
        guard !busy, !bundles.isEmpty else { return }
        forget(bundles)
        busy = true
        let own = bundles.filter(\.isUserLevel)
        let shared = bundles.filter { !$0.isUserLevel }
        queue.async {
            var done = 0
            var failed: [String] = []
            for bundle in own { self.trashOwn(bundle.url, &done, &failed) }
            var result: Shell.Result?
            if !shared.isEmpty {
                let run = self.runner(["--trash"] + shared.map(\.url.path), true, Shell.ownerEnv)
                done += Self.lines(run, "trashed: ").count
                failed += Self.failures(run)
                result = run
            }
            let status = Self.outcome(done: done, failed: failed, result: result, success: .trashed(done))
            DispatchQueue.main.async {
                self.busy = false
                self.status = status
                self.scan()
            }
        }
    }

    private func trashOwn(_ url: URL, _ done: inout Int, _ failed: inout [String]) {
        do {
            try trasher(url)
            done += 1
        } catch {
            failed.append(url.path)
        }
    }

    // MARK: - Reading what the script did

    /// What follows `prefix` on the lines that start with it.
    private static func lines(_ result: Shell.Result, _ prefix: String) -> [String] {
        result.output.split(separator: "\n").filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    /// What the script says it didn't do.
    private static func failures(_ result: Shell.Result) -> [String] {
        lines(result, "failed: ") + lines(result, "skip: ")
    }

    /// The status of a job that may have done part of its work. `result` is nil when no script was needed.
    static func outcome(done: Int, failed: [String], result: Shell.Result?, success: ManagerStatus) -> ManagerStatus {
        if let result = result, result.cancelled, done == 0 { return .cancelled }
        if !failed.isEmpty { return done > 0 ? .partly(done: done, failed: failed) : .failed(failed.joined(separator: "\n")) }
        if let result = result, !result.succeeded { return result.cancelled ? .partly(done: done, failed: []) : .failed(result.error) }
        return success
    }
}

/// Plugins in ~/Library/Audio/Plug-Ins belong to the user, and the root script stays out of them.
enum UserPlugins {
    /// Moves a bundle to `root`/Disabled or back. Nothing is overwritten.
    static func setDisabled(_ bundle: PluginBundle, _ disabled: Bool, root: URL) throws {
        let target: URL
        if disabled {
            let relative = String(bundle.url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
            target = root.appendingPathComponent(PluginInventory.disabledFolder, isDirectory: true).appendingPathComponent(relative)
        } else {
            target = bundle.enabledURL
        }
        try relocate(from: bundle.url, to: target)
    }

    static func relocate(from: URL, to: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: to.path) else { throw CocoaError(.fileWriteFileExists) }
        try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: from, to: to)
    }

    static func unquarantine(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) < 0 else { throw CocoaError(.fileWriteNoPermission) }
    }
}
