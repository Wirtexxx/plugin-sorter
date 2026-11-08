import Foundation
import AppKit
import AVFoundation
import CryptoKit

enum FLStatus: Equatable {
    case idle
    /// `failed`: favourites that ended up with no picture at all.
    case done(shots: Int, cards: Int, failed: Int)
    /// Screenshots for the app's own collection: taken, and the names of the plugins that wouldn't open.
    case captured(shots: Int, failed: [String])
    case removed(Int)
    case failed(String)
}

/// State of the FL Studio tab: favourites in FL's plugin database and their pictures.
final class FLLibrary: ObservableObject {
    @Published var plugins: [FLPlugin] = []
    @Published var busy = false
    /// The first scan has finished, so `plugins` says what is really there.
    @Published private var scanned = false
    var loaded: Bool { demo || scanned }
    @Published var progress = 0.0
    @Published var current = ""
    @Published var status: FLStatus = .idle
    /// Plugins with a screenshot of the app's own, kept here because the window asks on every redraw.
    @Published private(set) var localKeys: Set<String> = []
    /// How far a job that opens plugins one by one has got. These can be stopped.
    @Published private(set) var capture: CheckProgress?
    var capturingAll: Bool { capture != nil }
    /// The running job reads the shared database rather than opening plugins.
    @Published private(set) var downloading = false
    /// Asked to stop; the plugin open now still finishes. Only touched on the main thread.
    @Published private(set) var stopRequested = false

    private let local: LocalPictures
    /// A screenshot of a plugin; the real one opens it in a helper.
    private let shooter: ((ManagedPlugin) -> Data?)?
    /// Reads a file of the shared picture database; nil on any failure. Runs off the main thread.
    private let fetch: (URL) -> Data?
    /// Pictures of single plugins don't wait behind a capture of everything.
    private let writes = DispatchQueue(label: "plugin-sorter.fl-writes", qos: .userInitiated)
    private let scans = ScanGate()
    private let manifest = PictureManifest.shared
    private let queue = DispatchQueue(label: "plugin-sorter.fl", qos: .userInitiated)
    private let demo: Bool

    init(demo: Bool = false, local: LocalPictures = LocalPictures(), shooter: ((ManagedPlugin) -> Data?)? = nil,
         fetch: ((URL) -> Data?)? = nil) {
        self.demo = demo
        self.local = local
        self.shooter = shooter
        self.fetch = fetch ?? Self.download
        if !demo { localKeys = local.keys }
    }

    func failedKeys(among plugins: [ManagedPlugin]) -> Set<String> { local.failedKeys(among: plugins) }

    /// Gives every plugin that wouldn't open another try.
    func forgetFailedShots() {
        local.forgetFailures()
        objectWillChange.send()
    }

    /// The plugin is gone, so its screenshot has no use.
    func removeLocalPicture(of key: String) {
        local.remove(key)
        localKeys.remove(key)
    }

    func localPicture(of key: String) -> URL? { localKeys.contains(key) ? local.url(for: key) : nil }

    var missing: [FLPlugin] { plugins.filter { !$0.hasPicture } }
    var mine: [FLPlugin] { plugins.filter { $0.source != nil } }

    /// Reads FL's database off the main thread; hundreds of .fst files would otherwise stall the window.
    func scan() {
        guard !demo else { return }
        guard FLDatabase.exists else { plugins = []; scanned = true; return }
        guard scans.request() else { return }
        queue.async {
            self.scans.started()
            let plugins = FLDatabase.scan(self.manifest)
            DispatchQueue.main.async {
                self.plugins = plugins
                self.scanned = true
            }
        }
    }

    /// Screenshots for the app's own collection, whether or not the plugins are favourites.
    /// FL's files stay as they are.
    /// - Parameter next: runs once the capture is over, unless it was stopped.
    func captureAll(_ targets: [ManagedPlugin], then next: (() -> Void)? = nil) {
        guard !busy else { return }
        guard !targets.isEmpty else { next?(); return }
        busy = true
        capture = CheckProgress(done: 0, total: targets.count, current: "")
        stopRequested = false
        progress = 0
        queue.async {
            let shoot = self.shooter ?? Self.realShooter()
            var shots = 0
            var failed: [ManagedPlugin] = []
            for (n, plugin) in targets.enumerated() {
                if DispatchQueue.main.sync(execute: { self.stopRequested }) { break }
                DispatchQueue.main.async {
                    self.current = plugin.name
                    self.progress = Double(n) / Double(targets.count)
                    self.capture = CheckProgress(done: n, total: targets.count, current: plugin.name)
                }
                if let png = shoot(plugin), (try? self.local.save(png, for: plugin.key)) != nil {
                    shots += 1
                    DispatchQueue.main.async { self.localKeys.insert(plugin.key) }
                } else {
                    failed.append(plugin)
                }
            }
            self.local.noteFailures(failed)
            DispatchQueue.main.async {
                self.busy = false
                self.capture = nil
                self.current = ""
                self.status = .captured(shots: shots, failed: failed.map(\.name))
                if !self.stopRequested { next?() }
            }
        }
    }

    private static func realShooter() -> (ManagedPlugin) -> Data? {
        let components = PluginCapture.components()
        return { plugin in PluginCapture.match(plugin, in: components).flatMap { PluginCapture.capture($0) } }
    }

    /// Stops after the plugin being opened now.
    func stopCapture() { stopRequested = true }

    /// Pictures from the shared database for plugins that have none, so fewer plugins need opening.
    /// Anything that goes wrong just leaves the plugin to the capture that follows; nothing is reported.
    /// - Parameter wanted: the key a picture is kept under, and the keys to look it up by in the index.
    /// - Parameter next: runs once the downloads are over, unless they were stopped.
    func fetchFromDatabase(_ wanted: [String: [String]], then next: @escaping () -> Void) {
        guard !busy else { return }
        guard !wanted.isEmpty else { next(); return }
        busy = true
        downloading = true
        stopRequested = false
        progress = 0
        queue.async {
            let index = self.fetch(PictureDatabase.indexURL).flatMap(PictureIndex.parse)
            let have = self.local.keys
            let plan: [(key: String, entry: PictureIndex.Entry)] = wanted.sorted { $0.key < $1.key }.compactMap { key, candidates in
                let action = PictureDatabase.action(candidates: candidates, hasLocal: have.contains(key),
                                                    downloadedSHA: self.local.downloadedSHA(of: key), index: index)
                guard case .download(_, let entry) = action else { return nil }
                return (key, entry)
            }
            for (n, item) in plan.enumerated() {
                if DispatchQueue.main.sync(execute: { self.stopRequested }) { break }
                DispatchQueue.main.async {
                    self.progress = Double(n) / Double(plan.count)
                    self.capture = CheckProgress(done: n, total: plan.count, current: "")
                }
                guard let url = PictureDatabase.url(of: item.entry), let data = self.fetch(url),
                      Self.sha256(data) == item.entry.sha256, NSImage(data: data) != nil,
                      (try? self.local.saveDownloaded(data, for: item.key, sha256: item.entry.sha256)) != nil else { continue }
                DispatchQueue.main.async { self.localKeys.insert(item.key) }
            }
            DispatchQueue.main.async {
                self.busy = false
                self.downloading = false
                self.capture = nil
                if !self.stopRequested { next() }
            }
        }
    }

    /// The author's tool: full-size shots of the plugins the database in `folder` lacks, written there
    /// with an updated index. Opens plugins like a capture of everything, and can be stopped the same way.
    func exportForDatabase(_ plugins: [ManagedPlugin], waves: [FLPlugin], into folder: URL) {
        guard !busy else { return }
        busy = true
        stopRequested = false
        progress = 0
        queue.async {
            let have = (try? Data(contentsOf: folder.appendingPathComponent("index.json"))).flatMap(PictureIndex.parse)
            let components = PluginCapture.components()
            var jobs: [(name: String, keys: [String], component: AVAudioUnitComponent?)] = []
            for plugin in plugins where have?.entry(for: plugin.pictureKeys) == nil {
                jobs.append((plugin.name, plugin.pictureKeys, PluginCapture.match(plugin, in: components)))
            }
            for plugin in waves where have?.entry(for: [PictureKey.waves(plugin.title)]) == nil {
                jobs.append((plugin.title, [PictureKey.waves(plugin.title)], PluginCapture.match(plugin, in: components)))
            }
            var shots: [(keys: [String], png: Data)] = []
            var failed: [String] = []
            for (n, job) in jobs.enumerated() {
                if DispatchQueue.main.sync(execute: { self.stopRequested }) { break }
                DispatchQueue.main.async {
                    self.current = job.name
                    self.progress = Double(n) / Double(jobs.count)
                    self.capture = CheckProgress(done: n, total: jobs.count, current: job.name)
                }
                let size = Int(Thumbnail.databaseSize.width)
                if let component = job.component, let png = PluginCapture.capture(component, maxSide: size) {
                    shots.append((job.keys, png))
                } else {
                    failed.append(job.name)
                }
            }
            // Written even after a stop: what was shot so far is worth keeping
            let result = Result { try PictureExport.export(shots, into: folder) }
            DispatchQueue.main.async {
                self.busy = false
                self.capture = nil
                self.current = ""
                switch result {
                case .success(let written): self.status = .captured(shots: written, failed: failed)
                case .failure(let error):   self.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Pictures that came from the database, to look up again: the author may have replaced them.
    /// Reads the disk. Plugins' own screenshots are left out, the database never replaces those.
    func downloadedPictures(among plugins: [ManagedPlugin]) -> [String: [String]] {
        var wanted: [String: [String]] = [:]
        for plugin in plugins where local.downloadedSHA(of: plugin.key) != nil { wanted[plugin.key] = plugin.pictureKeys }
        for key in local.keys where key.hasPrefix(PictureKey.waves("")) && local.downloadedSHA(of: key) != nil {
            wanted[key] = [key]
        }
        return wanted
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Plain HTTPS without cookies or a cache of its own; gives up after 15 seconds.
    private static func download(_ url: URL) -> Data? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        var result: Data?
        let done = DispatchSemaphore(value: 0)
        session.dataTask(with: url) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 { result = data }
            done.signal()
        }.resume()
        done.wait()
        return result
    }

    /// A plugin just became a favourite: its screenshot goes into FL, unless a picture is already there.
    func adopt(_ shot: URL, for fst: URL) {
        writes.async {
            let plugin = FLPlugin(fst: fst, title: fst.deletingPathExtension().lastPathComponent,
                                  info: FST.read(fst) ?? FSTInfo(), hasPicture: false, source: nil)
            guard !FileManager.default.fileExists(atPath: plugin.picture.path) else { return }
            guard let image = NSImage(contentsOf: shot),
                  let png = DispatchQueue.main.sync(execute: {
                      FLCard.png(title: plugin.title, vendor: plugin.info.vendor, shot: image)
                  }) else {
                DispatchQueue.main.async { self.status = .failed(shot.lastPathComponent) }
                return
            }
            let result = Result { try FLDatabase.install(png, for: plugin, source: .screenshot, manifest: self.manifest) }
            DispatchQueue.main.async {
                if case .failure(let error) = result { self.status = .failed(error.localizedDescription) }
                self.scan()
            }
        }
    }

    /// - Parameter local: screenshots already taken, by favourite; these plugins aren't opened again.
    func generate(_ targets: [FLPlugin], screenshots: Bool, local: [String: URL] = [:]) {
        guard !busy, !targets.isEmpty else { return }
        busy = true
        progress = 0
        // Only a run that opens plugins takes long enough to need stopping
        let stoppable = screenshots && targets.count > 1
        if stoppable { capture = CheckProgress(done: 0, total: targets.count, current: "") }
        stopRequested = false
        queue.async {
            let components = screenshots ? PluginCapture.components() : []
            var shots = 0, cards = 0, failed = 0
            for (n, plugin) in targets.enumerated() {
                if DispatchQueue.main.sync(execute: { self.stopRequested }) { break }
                DispatchQueue.main.async {
                    self.current = plugin.title
                    self.progress = Double(n) / Double(targets.count)
                    if stoppable { self.capture = CheckProgress(done: n, total: targets.count, current: plugin.title) }
                }
                var shot = local[plugin.id].flatMap { NSImage(contentsOf: $0) }
                if shot == nil, screenshots, let component = PluginCapture.match(plugin, in: components),
                   let capture = PluginCapture.capture(component) {
                    shot = NSImage(data: capture)
                }
                let source: FLPlugin.Source = shot == nil ? .card : .screenshot
                let png = DispatchQueue.main.sync {
                    FLCard.png(title: plugin.title, vendor: plugin.info.vendor, shot: shot)
                }
                guard let data = png, (try? FLDatabase.install(data, for: plugin, source: source, manifest: self.manifest)) != nil else {
                    failed += 1
                    continue
                }
                if source == .screenshot { shots += 1 } else { cards += 1 }
            }
            DispatchQueue.main.async {
                self.busy = false
                self.capture = nil
                self.current = ""
                self.status = .done(shots: shots, cards: cards, failed: failed)
                self.scan()
            }
        }
    }

    func setCustom(_ plugin: FLPlugin, image url: URL) {
        writes.async {
            // Custom images go into the same template as screenshots
            let image = NSImage(contentsOf: url)
            let png = image.flatMap { image in
                DispatchQueue.main.sync { FLCard.png(title: plugin.title, vendor: plugin.info.vendor, shot: image) }
            }
            guard let png = png else {
                DispatchQueue.main.async { self.status = .failed(url.lastPathComponent) }
                return
            }
            let result = Result { try FLDatabase.install(png, for: plugin, source: .custom, manifest: self.manifest) }
            DispatchQueue.main.async {
                if case .failure(let error) = result { self.status = .failed(error.localizedDescription) }
                self.scan()
            }
        }
    }

    func remove(_ targets: [FLPlugin]) {
        writes.async {
            let result = Result { for target in targets { try FLDatabase.remove(target, manifest: self.manifest) } }
            DispatchQueue.main.async {
                switch result {
                case .success:            self.status = .removed(targets.count)
                case .failure(let error): self.status = .failed(error.localizedDescription)
                }
                self.scan()
            }
        }
    }
}
