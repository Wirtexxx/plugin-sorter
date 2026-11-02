// Renders the main window with demo data for the README: snapshot <out.png> [lang] [sorter|fl]
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

        let tab = CommandLine.arguments.count > 3 ? Tab(rawValue: CommandLine.arguments[3]) ?? .sorter : .sorter
        let library = demoLibrary()

        let size = NSSize(width: 900, height: 640)
        let root = ZStack {
            Color.chassis
            ContentView(sorter: sorter, library: library, tab: tab)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12))

        let view = NSHostingView(rootView: root)
        view.frame = NSRect(origin: .zero, size: size)
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
                let shot = shots.flatMap { try? Data(contentsOf: $0.appendingPathComponent(title.replacingOccurrences(of: " ", with: "_") + ".png")) }
                try? (shot ?? FLCard.png(title: title, vendor: vendor))?.write(to: picture)
            }
            return FLPlugin(fst: fst, title: title, info: FSTInfo(name: title, vendor: vendor, path: ""),
                            hasPicture: source != nil, source: source)
        }
        library.status = .done(shots: 5, cards: 2)
        return library
    }
}
