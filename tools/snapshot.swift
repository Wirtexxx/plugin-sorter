// Renders the main window with demo data for the README: snapshot <out.png> [lang]
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
            ("FabFilter", "Pro-Q 4", ["VST3", "AU"]),
            ("FabFilter", "Pro-L 2", ["VST3", "AU"]),
            ("FabFilter", "Saturn 2", ["VST3"]),
            ("Valhalla DSP", "ValhallaSupermassive", ["VST3", "AU"]),
            ("Valhalla DSP", "ValhallaVintageVerb", ["AU"]),
            ("Xfer Records", "Serum2", ["VST3", "AU"]),
            ("Xfer Records", "OTT", ["VST"]),
            ("iZotope", "Ozone 11 Maximizer", ["VST3", "AU"]),
            ("oeksound", "soothe2", ["VST3", "VST"]),
            ("Cableguys", "ShaperBox 3", ["AU"]),
        ]
        sorter.moves = demo.flatMap { vendor, plugin, formats in
            formats.map { Move(plugin: plugin, vendor: vendor, format: $0) }
        }
        sorter.notes = [Note(kind: .waves, text: "WaveShell1-AU 17.1.component")]
        sorter.status = .willMove(sorter.moves.count)

        let size = NSSize(width: 900, height: 640)
        let root = ZStack {
            Color.chassis
            ContentView(sorter: sorter)
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
}
