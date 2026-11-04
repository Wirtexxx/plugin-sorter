import Foundation
import AppKit
import AVFoundation

enum FLStatus: Equatable {
    case idle
    case done(shots: Int, cards: Int)
    /// Screenshots for the app's own collection: taken, and plugins that wouldn't open.
    case captured(shots: Int, failed: Int)
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
    /// How far `captureAll` has got, the one job that can be stopped.
    @Published private(set) var capture: CheckProgress?
    var capturingAll: Bool { capture != nil }
    /// Asked to stop; the plugin open now still finishes. Only touched on the main thread.
    @Published private(set) var stopRequested = false

    private let local = LocalPictures()
    private let scans = ScanGate()
    private let manifest = PictureManifest.shared
    private let queue = DispatchQueue(label: "plugin-sorter.fl", qos: .userInitiated)
    private let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
        if !demo { localKeys = local.keys }
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

    /// Screenshot for every plugin without a picture, card when that fails.
    func generateMissing() {
        generate(missing, screenshots: true)
    }

    /// Screenshots for the app's own collection, whether or not the plugins are favourites.
    /// FL's files stay as they are.
    func captureAll(_ targets: [ManagedPlugin]) {
        guard !busy, !targets.isEmpty else { return }
        busy = true
        capture = CheckProgress(done: 0, total: targets.count, current: "")
        stopRequested = false
        progress = 0
        queue.async {
            let components = PluginCapture.components()
            var shots = 0, failed = 0
            for (n, plugin) in targets.enumerated() {
                if DispatchQueue.main.sync(execute: { self.stopRequested }) { break }
                DispatchQueue.main.async {
                    self.current = plugin.name
                    self.progress = Double(n) / Double(targets.count)
                    self.capture = CheckProgress(done: n, total: targets.count, current: plugin.name)
                }
                if let component = PluginCapture.match(plugin, in: components),
                   let png = PluginCapture.capture(component),
                   (try? self.local.save(png, for: plugin.key)) != nil {
                    shots += 1
                    DispatchQueue.main.async { self.localKeys.insert(plugin.key) }
                } else {
                    failed += 1
                }
            }
            DispatchQueue.main.async {
                self.busy = false
                self.capture = nil
                self.current = ""
                self.status = .captured(shots: shots, failed: failed)
            }
        }
    }

    /// Stops after the plugin being captured now.
    func stopCapture() { stopRequested = true }

    /// A plugin just became a favourite: its screenshot goes into FL, unless a picture is already there.
    func adopt(_ shot: URL, for fst: URL) {
        queue.async {
            let plugin = FLPlugin(fst: fst, title: fst.deletingPathExtension().lastPathComponent,
                                  info: FST.read(fst) ?? FSTInfo(), hasPicture: false, source: nil)
            guard !FileManager.default.fileExists(atPath: plugin.picture.path),
                  let image = NSImage(contentsOf: shot),
                  let png = DispatchQueue.main.sync(execute: {
                      FLCard.png(title: plugin.title, vendor: plugin.info.vendor, shot: image)
                  }) else { return }
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
        queue.async {
            let components = screenshots ? PluginCapture.components() : []
            var shots = 0, cards = 0
            for (n, plugin) in targets.enumerated() {
                DispatchQueue.main.async {
                    self.current = plugin.title
                    self.progress = Double(n) / Double(targets.count)
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
                guard let data = png, (try? FLDatabase.install(data, for: plugin, source: source, manifest: self.manifest)) != nil else { continue }
                if source == .screenshot { shots += 1 } else { cards += 1 }
            }
            DispatchQueue.main.async {
                self.busy = false
                self.current = ""
                self.status = .done(shots: shots, cards: cards)
                self.scan()
            }
        }
    }

    func setCustom(_ plugin: FLPlugin, image url: URL) {
        queue.async {
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
        queue.async {
            targets.forEach { FLDatabase.remove($0, manifest: self.manifest) }
            DispatchQueue.main.async {
                self.status = .removed(targets.count)
                self.scan()
            }
        }
    }
}
