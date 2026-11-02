// Renders the main window with demo data for the README:
// snapshot <out.png> [lang] [sorter|fl|manager|settings] [violet|mint|amber|ice]
import SwiftUI
import AppKit

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

        let mode = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "sorter"
        let tab = Tab(rawValue: mode) ?? .sorter
        // Real FL pictures only on request: they show other vendors' interfaces, not for the README
        if ProcessInfo.processInfo.environment["PS_THUMBS"] != nil {
            Thumbnails.shared.load()
            RunLoop.main.run(until: Date().addingTimeInterval(2))
        }
        let library = demoLibrary()
        let manager = demoManager()

        let view: NSView
        if mode == "settings" {
            let settings = NSHostingView(rootView: ZStack { Color.chassis; SettingsView() }
                .clipShape(RoundedRectangle(cornerRadius: 12)))
            settings.frame = NSRect(origin: .zero, size: settings.fittingSize)
            view = settings
        } else {
            let size = NSSize(width: 900, height: 640)
            let main = NSHostingView(rootView: ZStack {
                Color.chassis
                ContentView(sorter: sorter, library: library, manager: manager, tab: tab)
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
        manager.expanded = ["Serum2"]
        manager.status = .checked(ok: 4, warnings: 1, failed: 2)
        return manager
    }

    /// FL tab demo: generated cards, plus real screenshots from $PS_SHOTS/<title>.png when given.
    private static func demoLibrary() -> FLLibrary {
        let library = FLLibrary(demo: true)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("plugin-sorter-demo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let shots = ProcessInfo.processInfo.environment["PS_SHOTS"].map { URL(fileURLWithPath: $0) }

        let demo: [(String, String, FLPlugin.Source?)] = [
            ("Pro-Q 4", "FabFilter", .screenshot), ("ValhallaSupermassive", "Valhalla DSP", .screenshot),
            ("OTT", "Xfer Records", .screenshot), ("soothe2", "oeksound", .screenshot),
            ("kHs Chorus", "Kilohearts", .screenshot), ("CLA-76 Stereo", "Waves", .card),
            ("GClip", "GVST", .card), ("Serum 2", "Xfer Records", nil),
        ]
        library.plugins = demo.map { title, vendor, source in
            let fst = dir.appendingPathComponent(title + ".fst")
            let picture = fst.deletingPathExtension().appendingPathExtension("png")
            try? FileManager.default.removeItem(at: picture)
            if source != nil {
                let shot = shots.flatMap { NSImage(contentsOf: $0.appendingPathComponent(title.replacingOccurrences(of: " ", with: "_") + ".png")) }
                try? FLCard.png(title: title, vendor: vendor, shot: shot)?.write(to: picture)
            }
            return FLPlugin(fst: fst, title: title, info: FSTInfo(name: title, vendor: vendor, path: ""),
                            hasPicture: source != nil, source: source)
        }
        library.status = .done(shots: 5, cards: 2)
        return library
    }
}
