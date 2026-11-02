import SwiftUI
import AppKit

/// Fallback picture for plugins whose interface can't be captured.
struct FLCard: View {
    static let size = CGSize(width: 256, height: 128)

    let title: String
    let vendor: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(vendor.uppercased()).caption().lineLimit(1)
                Spacer()
                StatusDot()
            }
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            WaveBars(levels: levels, mirrored: false)
                .fill(LinearGradient(gradient: Gradient(colors: [Color.accentHot, Color.accent.opacity(0.4)]),
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 38)
        }
        .padding(14)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color.panel)
    }

    /// Bars seeded by the title so every plugin gets its own stable wave.
    private var levels: [CGFloat] {
        var seed = title.unicodeScalars.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1.value) }
        return (0..<40).map { i in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let random = CGFloat(seed >> 33) / CGFloat(UInt32.max)
            let envelope = sin(CGFloat(i) / 39 * .pi)
            return 0.15 + 0.85 * envelope * (0.5 + 0.5 * random)
        }
    }

    /// Renders the card offscreen. Must run on the main thread.
    static func png(title: String, vendor: String) -> Data? {
        let view = NSHostingView(rootView: FLCard(title: title, vendor: vendor))
        view.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage.flatMap { Thumbnail.png($0, fitting: size) }
    }
}

enum Thumbnail {
    /// FL's stock pictures are small crops of the plugin window, around 250 px wide.
    static let maxSize = CGSize(width: 256, height: 160)

    static func png(_ image: CGImage, fitting box: CGSize = maxSize) -> Data? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let scale = min(box.width / w, box.height / h, 1)
        let width = max(Int((w * scale).rounded()), 1)
        let height = max(Int((h * scale).rounded()), 1)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
    }

    static func png(fromFile url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return png(cg)
    }

    /// True for empty captures: a single flat colour, usually black or transparent.
    static func isBlank(_ image: CGImage) -> Bool {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return true }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let luma = stride(from: 0, to: pixels.count, by: 4).map {
            0.3 * Double(pixels[$0]) + 0.59 * Double(pixels[$0 + 1]) + 0.11 * Double(pixels[$0 + 2])
        }
        let mean = luma.reduce(0, +) / Double(luma.count)
        let variance = luma.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(luma.count)
        return variance.squareRoot() < 4
    }
}
