// Draws the 1024×1024 app icon: icon <out.png>
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

// macOS icon grid: 824 square with 185 corner radius
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(colors: [rgb(0.16, 0.05, 0.30), rgb(0.03, 0.02, 0.06)])!
    .draw(in: tile, relativeCenterPosition: NSPoint(x: 0, y: 0.1))

NSGraphicsContext.current!.saveGraphicsState()
tile.addClip()

// Stars
for i in 0..<70 {
    func noise(_ seed: Double) -> CGFloat {
        let v = sin(Double(i + 1) * seed) * 43758.5453
        return CGFloat(v - v.rounded(.down))
    }
    let s = 2 + noise(39.3) * 5
    rgb(1, 1, 1, 0.2 + noise(93.9) * 0.6).setFill()
    NSBezierPath(ovalIn: NSRect(x: 100 + noise(12.9) * 824, y: 100 + noise(78.2) * 824, width: s, height: s)).fill()
}

// Glow behind the planet
NSGradient(colors: [rgb(0.80, 0.30, 1.00, 0.55), rgb(0.48, 0.20, 0.97, 0)])!
    .draw(in: NSBezierPath(ovalIn: NSRect(x: 162, y: 162, width: 700, height: 700)), relativeCenterPosition: .zero)

// Planet
let planetRect = NSRect(x: 262, y: 262, width: 500, height: 500)
NSGradient(colors: [rgb(1, 0.92, 1), rgb(0.80, 0.30, 1.00), rgb(0.40, 0.14, 0.85), rgb(0.06, 0.02, 0.14)],
           atLocations: [0, 0.25, 0.65, 1], colorSpace: .deviceRGB)!
    .draw(in: NSBezierPath(ovalIn: planetRect), relativeCenterPosition: NSPoint(x: -0.4, y: 0.45))

// Ring
let ring = NSBezierPath(ovalIn: NSRect(x: -360, y: -80, width: 720, height: 160))
var transform = AffineTransform(translationByX: 512, byY: 512)
transform.rotate(byDegrees: 20)
ring.transform(using: transform)
ring.lineWidth = 16
rgb(0.45, 0.78, 1.00, 0.85).setStroke()
ring.stroke()

NSGraphicsContext.current!.restoreGraphicsState()

// Folder symbol
if let symbol = NSImage(systemSymbolName: "folder.fill.badge.gearshape", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 210, weight: .semibold)) {
    let white = NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    let s = white.size
    white.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
