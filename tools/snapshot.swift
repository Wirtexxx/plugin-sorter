// Renders the main window with demo data for the README:
// snapshot <out.png> [lang] [main|main-expanded|cards|cards-panel|banner|sheet|settings] [violet|mint|amber|ice]
import SwiftUI
import AppKit

/// Licenses of the demo live in memory: a snapshot must never reach the real Keychain.
final class DemoSecrets: SecretStore {
    private var records: [String: Data] = [:]
    func accounts() throws -> Set<String> { Set(records.keys) }
    func read(_ account: String) throws -> Data? { records[account] }
    func write(_ data: Data, account: String) throws { records[account] = data }
    func delete(_ account: String) throws { records[account] = nil }
}

@main
struct Snapshot {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "screenshot.png"
        if CommandLine.arguments.count > 2 {
            UserDefaults.standard.set(CommandLine.arguments[2], forKey: "language")
        }
        // Always set the skin: UserDefaults persist between runs of this tool
        UserDefaults.standard.set(CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : Skin.violet.rawValue,
                                  forKey: Skin.key)

        let sorter = Sorter(demo: true)
        let demo: [(String, String, [String])] = [
            ("FabFilter", "Pro-Q 4", ["VST3"]),
            ("FabFilter", "Pro-L 2", ["VST3"]),
            ("FabFilter", "Saturn 2", ["VST3", "VST"]),
            ("FabFilter", "Timeless 3", ["VST3"]),
            ("Valhalla DSP", "ValhallaSupermassive", ["VST3"]),
            ("Valhalla DSP", "ValhallaVintageVerb", ["VST3"]),
            ("Xfer Records", "Serum2", ["VST3"]),
            ("Xfer Records", "OTT", ["VST3", "VST"]),
            ("iZotope", "Ozone 11 Maximizer", ["VST3"]),
            ("oeksound", "soothe2", ["VST3", "VST"]),
            ("Cableguys", "ShaperBox 3", ["VST3"]),
        ]
        sorter.moves = demo.flatMap { vendor, plugin, formats in
            formats.map { Move(plugin: plugin, vendor: vendor, format: $0) }
        }
        sorter.notes = [Note(kind: .waves, text: "WaveShell1-AU 17.1.component")]
        sorter.status = .willMove(sorter.moves.count)

        let mode = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "main"

        let model: AppModel
        // The real plugins and FL database, for local checks only (PS_REAL=1)
        if ProcessInfo.processInfo.environment["PS_REAL"] != nil {
            model = AppModel()
            model.refresh()
            RunLoop.main.run(until: Date().addingTimeInterval(8))
        } else {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("plugin-sorter-demo", isDirectory: true)
            let manager = demoManager()
            let (favorites, titles) = demoFavorites(for: manager, in: dir)
            model = AppModel(sorter: sorter, manager: manager, favorites: favorites, pictures: demoLibrary(titles, in: dir),
                             known: KnownPlugins(url: dir.appendingPathComponent("known-plugins.json")),
                             labels: UserLabels(url: dir.appendingPathComponent("labels.json")),
                             vault: LicenseVault(store: DemoSecrets()))
            model.flRoot = dir
        }
        // Always set the view: UserDefaults persist between runs of this tool
        UserDefaults.standard.set(mode.hasPrefix("cards") ? "cards" : "list", forKey: "viewMode")
        if mode == "cards-panel" {
            model.expanded = model.rows.first { $0.name == "Serum2" }?.id
        }
        if mode == "banner" {
            model.banner = Banner(source: .favorites(.sorted(12)), isError: false, undo: {})
        }
        if mode == "main-expanded" {
            model.expanded = model.rows.first { $0.name == "Serum2" }?.id ?? model.rows.first?.id
        }

        let view: NSView
        let t = L10n(lang: Lang(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .en)
        if mode == "sheet" {
            let sheet = NSHostingView(rootView: FolderSortSheet(model: model, t: t).clipShape(RoundedRectangle(cornerRadius: 12)))
            sheet.frame = NSRect(origin: .zero, size: sheet.fittingSize)
            view = sheet
        } else if mode == "settings" {
            let settings = NSHostingView(rootView: ZStack { Color.chassis; SettingsView() }
                .clipShape(RoundedRectangle(cornerRadius: 12)))
            settings.frame = NSRect(origin: .zero, size: settings.fittingSize)
            view = settings
        } else {
            let size = NSSize(width: 900, height: 640)
            let main = NSHostingView(rootView: ZStack {
                Color.chassis
                MainView(model: model, t: t)
                    .padding(10)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12)))
            main.frame = NSRect(origin: .zero, size: size)
            view = main
        }
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .clear
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: output))
        print("Saved \(output)")
    }

    /// Manager tab demo: a few plugins with check results, one broken AU expanded.
    private static func demoManager() -> ManagerLibrary {
        let manager = ManagerLibrary(demo: true)
        let root = PluginInventory.root
        let demo: [(String, String, String, [(PluginFormat, [Issue]?)])] = [
            ("FabFilter Pro-Q 4", "FabFilter", "4.13", [(.au, []), (.clap, []), (.vst3, [])]),
            ("OTT", "Xfer Records", "1.37", [(.au, []), (.vst, []), (.vst3, [])]),
            ("Serum2", "Xfer Records", "2.0.15", [(.au, [.validationFailed("Error: could not load /Library/Audio/Plug-Ins/VST3/Serum2.vst3")]), (.vst3, [])]),
            ("soothe2", "oeksound", "1.4.2", [(.au, []), (.vst3, [])]),
            ("OldReverb", "Legacy Audio", "1.2", [(.vst, [.wrongArch(["i386"])])]),
            ("ValhallaSupermassive", "Valhalla DSP", "5.0.0", [(.au, []), (.vst3, [])]),
            ("kHs Chorus", "Kilohearts", "2.2.4", [(.au, [.quarantined]), (.vst3, nil)]),
        ]
        manager.plugins = demo.map { name, vendor, version, formats in
            let bundles = formats.map { format, _ -> PluginBundle in
                // VST3s live in vendor folders, as after sorting; that's what broke Serum 2's AU
                let folder = format == .vst3 ? "\(format.folder)/\(vendor)" : format.folder
                return PluginBundle(url: root.appendingPathComponent("\(folder)/\(name).\(format.fileExtension)"),
                                    format: format, vendor: vendor, version: version, executable: nil,
                                    archs: ["x86_64", "arm64"], quarantined: false, au: nil, nested: format == .vst3)
            }
            for (bundle, (_, issues)) in zip(bundles, formats) {
                manager.results[bundle.id] = issues.map { .done($0) } ?? .unchecked
            }
            return ManagedPlugin(key: name, name: name, vendor: vendor, bundles: bundles)
        }
        return manager
    }

    /// FL's view of the demo plugins: scanned as VST3, most of them favourites, some in categories.
    private static func demoFavorites(for manager: ManagerLibrary, in dir: URL) -> (FavoritesLibrary, [String: String]) {
        let categories: [String: String?] = [
            "FabFilter Pro-Q 4": "Filter", "OTT": "Dynamics", "Serum2": "Synth classic",
            "ValhallaSupermassive": "Delay reverb", "kHs Chorus": nil,
        ]
        var entries: [InstalledEntry] = []
        var favorites: [Favorite] = []
        var titles: [String: String] = [:]
        for plugin in manager.plugins where plugin.name != "OldReverb" {
            let section = plugin.name == "Serum2" ? "Generators" : "Effects"
            let bundle = plugin.bundles.first { $0.format == .vst3 } ?? plugin.bundles[0]
            let entry = InstalledEntry(fst: dir.appendingPathComponent("Installed/\(section)/VST3/\(plugin.name).fst"),
                                       section: section, format: "VST3", name: plugin.name, vendor: plugin.vendor,
                                       files: [bundle.url.path])
            entries.append(entry)
            guard let folder = categories[plugin.name] else { continue }
            let path = [section, folder, plugin.name + ".fst"].compactMap { $0 }.joined(separator: "/")
            favorites.append(Favorite(fst: dir.appendingPathComponent(path), title: plugin.name, section: section, entry: entry))
            titles[plugin.name] = dir.appendingPathComponent(path).path
        }
        return (FavoritesLibrary(demoEntries: entries, favorites: favorites), titles)
    }

    /// Pictures for the demo favourites: generated cards, plus real screenshots from $PS_SHOTS/<title>.png when given.
    private static func demoLibrary(_ favorites: [String: String], in dir: URL) -> FLLibrary {
        let library = FLLibrary(demo: true)
        let shots = ProcessInfo.processInfo.environment["PS_SHOTS"].map { URL(fileURLWithPath: $0) }
        library.plugins = favorites.sorted { $0.key < $1.key }.map { title, path in
            let fst = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(at: fst.deletingLastPathComponent(), withIntermediateDirectories: true)
            let picture = fst.deletingPathExtension().appendingPathExtension("png")
            let shot = shots.flatMap { NSImage(contentsOf: $0.appendingPathComponent(title.replacingOccurrences(of: " ", with: "_") + ".png")) }
            try? FLCard.png(title: title, vendor: "", shot: shot)?.write(to: picture)
            return FLPlugin(fst: fst, title: title, info: FSTInfo(name: title, vendor: "", path: ""),
                            hasPicture: true, source: shot == nil ? .card : .screenshot)
        }
        return library
    }
}
