import Foundation
import AppKit
import AVFoundation

enum FLStatus: Equatable {
    case idle
    case done(shots: Int, cards: Int)
    case removed(Int)
    case failed(String)
}

/// State of the FL Studio tab: favourites in FL's plugin database and their pictures.
final class FLLibrary: ObservableObject {
    @Published var plugins: [FLPlugin] = []
    @Published var busy = false
    @Published var progress = 0.0
    @Published var current = ""
    @Published var status: FLStatus = .idle

    private let manifest = PictureManifest.shared
    private let queue = DispatchQueue(label: "plugin-sorter.fl", qos: .userInitiated)
    private let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
    }

    var missing: [FLPlugin] { plugins.filter { !$0.hasPicture } }
    var mine: [FLPlugin] { plugins.filter { $0.source != nil } }

    /// Reads FL's database off the main thread; hundreds of .fst files would otherwise stall the window.
    func scan() {
        guard !demo else { return }
        guard FLDatabase.exists else { plugins = []; return }
        queue.async {
            let plugins = FLDatabase.scan(self.manifest)
            DispatchQueue.main.async { self.plugins = plugins }
        }
    }

    /// Screenshot for every plugin without a picture, card when that fails.
    func generateMissing() {
        generate(missing, screenshots: true)
    }

    func generate(_ targets: [FLPlugin], screenshots: Bool) {
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
                var shot: NSImage?
                if screenshots, let component = PluginCapture.match(plugin, in: components),
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
