import SwiftUI
import AppKit

/// "48,2 MB": file sizes the way Finder shows them.
func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

/// Honour System Settings → Accessibility → Display → Reduce motion.
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// An LED that pulses while something is being worked on.
struct PulseDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Color.accent)
            .frame(width: 7, height: 7)
            .opacity(on ? 1 : 0.25)
            .shadow(color: Color.accent.opacity(on ? 0.9 : 0), radius: 4)
            .onAppear {
                guard !Motion.reduced else { on = true; return }
                withAnimation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

// MARK: - Developer monogram

/// The developer's initials (FF, VD, XR…) in a graphite square, styled like the format chips
/// so it stays within the panel palette.
struct VendorBadge: View {
    let vendor: String
    var size: CGFloat = 20

    var body: some View {
        Text(Self.initials(vendor))
            .font(.system(size: size * 0.42, weight: .bold))
            .kerning(0.5)
            .foregroundColor(.text)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.raised))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.edge, lineWidth: 1))
    }

    /// "Xfer Records" → XR, "Valhalla DSP, LLC" → VD, "FabFilter" → FF, "oeksound" → OE.
    static func initials(_ vendor: String) -> String {
        let suffixes: Set<String> = ["llc", "inc", "ltd", "gmbh", "co", "corp"]
        let words = vendor.split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !suffixes.contains($0.lowercased()) }
        guard let first = words.first else { return "?" }
        if words.count >= 2, let a = words[0].first, let b = words[1].first {
            return String([a, b]).uppercased()
        }
        let capitals = first.filter(\.isUppercase)
        if capitals.count >= 2 { return String(capitals.prefix(2)) }
        return String(first.prefix(2)).uppercased()
    }
}

// MARK: - Plugin thumbnails

/// Pictures already made for FL Studio's browser, reused as previews in the app's lists.
final class Thumbnails: ObservableObject {
    static let shared = Thumbnails()

    @Published private(set) var index: [String: URL] = [:]
    private var images: [URL: NSImage] = [:]
    /// Off for README screenshots, which must not show other vendors' interfaces.
    var isEnabled = true

    func load() {
        guard isEnabled else { return }
        DispatchQueue.global(qos: .utility).async {
            var index: [String: URL] = [:]
            for plugin in FLDatabase.scan(PictureManifest()) where plugin.hasPicture {
                for name in [plugin.title, plugin.info.name] where !name.isEmpty {
                    index[Self.normalize(name)] = plugin.picture
                }
            }
            DispatchQueue.main.async {
                self.images = [:]
                self.index = index
            }
        }
    }

    /// Finds the picture for a plugin named like its file ("FabFilter Pro-Q 4") or like FL names it ("Pro-Q 4").
    func image(for name: String, vendor: String) -> NSImage? {
        let full = Self.normalize(name)
        let vendorKey = Self.normalize(vendor)
        var keys = [full]
        if !vendorKey.isEmpty && full.hasPrefix(vendorKey) && full.count > vendorKey.count {
            keys.append(String(full.dropFirst(vendorKey.count)))
        }
        guard let url = keys.lazy.compactMap({ self.index[$0] }).first else { return nil }
        if let cached = images[url] { return cached }
        let image = NSImage(contentsOf: url)
        images[url] = image
        return image
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// Keeps list columns aligned where a plugin has no picture yet.
struct ThumbPlaceholder: View {
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.chassis.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.edge.opacity(0.6), lineWidth: 1))
            .frame(width: width, height: height)
    }
}

/// A small preview of the plugin's interface: the screenshot part of its FL picture.
struct PluginThumb: View {
    let image: NSImage
    var width: CGFloat = 52
    var height: CGFloat = 24

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            // Our FL cards have the name on top; the interface is in the lower part
            .frame(width: width, height: height, alignment: .bottom)
            .clipped()
            .cornerRadius(3)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.edge, lineWidth: 1))
    }
}
