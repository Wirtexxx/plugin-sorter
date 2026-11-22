import AppKit

enum Thumbnail {
    /// Captures are handed from the helper to the app at this size, plenty for a 160 px card.
    static let captureSize = CGSize(width: 640, height: 640)
    /// Full-size shots for the shared picture database.
    static let databaseSize = CGSize(width: 2000, height: 2000)

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
