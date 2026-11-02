import SwiftUI
import AppKit

/// The picture FL shows for a plugin: a header with name and developer over a screenshot
/// of the plugin, or over a wave when no screenshot is available.
/// Every picture has the same size so FL's plugin picker lays them out as an even grid.
struct FLCard: View {
    /// Size FL draws the picture at. Its stock pictures average about 94×55 on screen.
    static let size = CGSize(width: 104, height: 64)
    /// Pixels per point. FL's stock PNGs are stored at 192 dpi, twice its 96 dpi base,
    /// and FL draws them at half their pixel size; a 72 dpi PNG is drawn pixel for pixel.
    static let scale: CGFloat = 2
    private static let header: CGFloat = 17

    let title: String
    let vendor: String
    var shot: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(vendor.uppercased())
                        .font(.system(size: 4.5, weight: .semibold))
                        .kerning(0.5)
                        .foregroundColor(.label)
                        .lineLimit(1)
                    Text(title)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                Circle()
                    .fill(Color.mint)
                    .frame(width: 3.5, height: 3.5)
                    .shadow(color: Color.mint.opacity(0.8), radius: 1.5)
            }
            .padding(.horizontal, 5)
            .frame(height: Self.header)

            ZStack {
                if let shot = shot {
                    Image(nsImage: shot)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    WaveBars(levels: levels, mirrored: false)
                        .fill(LinearGradient(gradient: Gradient(colors: [Color.accentHot, Color.accent.opacity(0.4)]),
                                             startPoint: .top, endPoint: .bottom))
                        .padding(.horizontal, 5)
                        .padding(.top, 9)
                }
            }
            // Anchor to the top: that's where plugins keep their logo and main controls
            .frame(width: Self.size.width, height: Self.size.height - Self.header, alignment: .top)
            .clipped()
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color.panel)
    }

    /// Bars seeded by the title so every plugin gets its own stable wave.
    private var levels: [CGFloat] {
        var seed: UInt64 = 5381
        for scalar in title.unicodeScalars {
            seed = (seed << 5) &+ seed &+ UInt64(scalar.value)
        }
        return (0..<40).map { i in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let random = CGFloat(seed >> 33) / CGFloat(UInt32.max)
            let envelope = sin(CGFloat(i) / 39 * .pi)
            return 0.15 + 0.85 * envelope * (0.5 + 0.5 * random)
        }
    }

    /// Renders the card offscreen. Must run on the main thread.
    static func png(title: String, vendor: String, shot: NSImage? = nil) -> Data? {
        let view = NSHostingView(rootView: FLCard(title: title, vendor: vendor, shot: shot))
        view.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        // Render at an exact 2x, independent of the screen the app runs on
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        // Store it at 192 dpi like FL's own pictures, so FL draws it at `size`
        rep.size = NSSize(width: CGFloat(rep.pixelsWide) * 72 / 192, height: CGFloat(rep.pixelsHigh) * 72 / 192)
        return rep.representation(using: .png, properties: [:]).map { padded($0) }
    }

    /// FL Studio ignores the 192 dpi of PNGs smaller than about 10 KB and draws them twice as large,
    /// which hits cards with plain screenshots. Pad them with a private ancillary chunk, which PNG
    /// decoders skip by definition, so every card stays the same size in FL's plugin picker.
    private static func padded(_ png: Data, to minimum: Int = 16_384) -> Data {
        let overhead = 12
        guard png.count + overhead < minimum, png.count > 12 else { return png }
        let body = Data(count: minimum - png.count - overhead)
        let type = Data("psOr".utf8)
        var chunk = Data()
        chunk.append(contentsOf: withUnsafeBytes(of: UInt32(body.count).bigEndian, Array.init))
        chunk.append(type)
        chunk.append(body)
        chunk.append(contentsOf: withUnsafeBytes(of: crc32(type + body).bigEndian, Array.init))
        // Insert right before the IEND chunk (its 4-byte length, "IEND" and 4-byte CRC)
        var out = png
        out.insert(contentsOf: chunk, at: png.count - 12)
        return out
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}

enum Thumbnail {
    /// Captures are handed from the helper to the app at this size, plenty for a 160 px card.
    static let captureSize = CGSize(width: 640, height: 640)

    static func png(_ image: CGImage, fitting box: CGSize) -> Data? {
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

    /// True for empty captures: a single flat colour, usually black or transparent.
    static func isBlank(_ image: CGImage) -> Bool {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return true }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        // Plain loops with explicit types: older compilers time out type-checking the closure version
        var luma: [Double] = []
        luma.reserveCapacity(side * side)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r: Double = Double(pixels[i])
            let g: Double = Double(pixels[i + 1])
            let b: Double = Double(pixels[i + 2])
            luma.append(0.3 * r + 0.59 * g + 0.11 * b)
        }
        var sum: Double = 0
        for value in luma { sum += value }
        let mean: Double = sum / Double(luma.count)
        var squares: Double = 0
        for value in luma { squares += (value - mean) * (value - mean) }
        let deviation: Double = (squares / Double(luma.count)).squareRoot()
        return deviation < 4
    }
}
