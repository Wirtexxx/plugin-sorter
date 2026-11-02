import Foundation
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
    @Published var showStock = false
    @Published var busy = false
    @Published var progress = 0.0
    @Published var current = ""
    @Published var status: FLStatus = .idle

    private let manifest = PictureManifest()
    private let queue = DispatchQueue(label: "plugin-sorter.fl", qos: .userInitiated)
    private let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
    }

    var visible: [FLPlugin] { showStock ? plugins : plugins.filter { !$0.isStock } }
    var missing: [FLPlugin] { plugins.filter { !$0.hasPicture } }
    var mine: [FLPlugin] { plugins.filter { $0.source != nil } }

    func scan() {
        guard !demo else { return }
        guard FLDatabase.exists else { plugins = []; return }
        plugins = FLDatabase.scan(manifest)
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
                var png: Data?
                var source = FLPlugin.Source.card
                if screenshots, let component = PluginCapture.match(plugin, in: components),
                   let shot = PluginCapture.capture(component) {
                    png = shot
                    source = .screenshot
                }
                if png == nil {
                    png = DispatchQueue.main.sync {
                        FLCard.png(title: plugin.title, vendor: plugin.info.vendor)
                    }
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
            guard let png = Thumbnail.png(fromFile: url) else {
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
