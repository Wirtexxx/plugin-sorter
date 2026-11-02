// Draws the 1024×1024 app icon: icon <out.png>
import AppKit

let size: CGFloat = 1024
let center = NSPoint(x: 512, y: 512)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

func arc(radius: CGFloat, from: CGFloat, to: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.appendArc(withCenter: center, radius: radius, startAngle: from, endAngle: to, clockwise: true)
    return path
}

// Graphite tile in the macOS icon grid (824 square, 185 radius)
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(colors: [hex(0x2E2E34), hex(0x1B1B1F)])!.draw(in: tile, angle: -90)
hex(0x3A3A41).setStroke()
tile.lineWidth = 4
tile.stroke()

// Knob scale: 270° track opening at the bottom, accent covering most of it
let track = arc(radius: 290, from: 225, to: -45)
track.lineWidth = 34
track.lineCapStyle = .round
hex(0x141417).setStroke()
track.stroke()

let value = arc(radius: 290, from: 225, to: 0)
value.lineWidth = 34
value.lineCapStyle = .round
NSGraphicsContext.current!.saveGraphicsState()
let glow = NSShadow()
glow.shadowColor = hex(0xA76BFF, 0.8)
glow.shadowBlurRadius = 40
glow.set()
hex(0xA76BFF).setStroke()
value.stroke()
NSGraphicsContext.current!.restoreGraphicsState()

// Knob cap
let cap = NSBezierPath(ovalIn: NSRect(x: 512 - 215, y: 512 - 215, width: 430, height: 430))
NSGraphicsContext.current!.saveGraphicsState()
let drop = NSShadow()
drop.shadowColor = NSColor.black.withAlphaComponent(0.6)
drop.shadowOffset = NSSize(width: 0, height: -14)
drop.shadowBlurRadius = 30
drop.set()
NSGradient(colors: [hex(0x404048), hex(0x25252A)])!.draw(in: cap, angle: -90)
NSGraphicsContext.current!.restoreGraphicsState()

// Folder glyph in the accent gradient
if let symbol = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 190, weight: .regular)) {
    let tinted = NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        NSGraphicsContext.current!.compositingOperation = .sourceAtop
        NSGradient(colors: [hex(0xE073FF), hex(0x3D6BFF)])!.draw(in: rect, angle: -60)
        return true
    }
    let s = tinted.size
    tinted.draw(in: NSRect(x: 512 - s.width / 2, y: 512 - s.height / 2, width: s.width, height: s.height))
}

// Status LED
NSGraphicsContext.current!.saveGraphicsState()
let led = NSShadow()
led.shadowColor = hex(0x3EE28A, 0.9)
led.shadowBlurRadius = 24
led.set()
hex(0x3EE28A).setFill()
NSBezierPath(ovalIn: NSRect(x: 770, y: 770, width: 44, height: 44)).fill()
NSGraphicsContext.current!.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
