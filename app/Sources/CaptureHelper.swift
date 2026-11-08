import AppKit
import AVFoundation
import AudioToolbox
import CoreAudioKit

/// The `--capture` helper: opens one Audio Unit's interface and writes a thumbnail of it.
enum CaptureHelper {
    private static var window: NSWindow?
    private static var viewController: NSViewController?
    /// The longest side a capture may have.
    private static var size = Thumbnail.captureSize

    /// An optional sixth argument asks for a larger longest side: the author's shots for the database.
    static func box(_ args: [String]) -> CGSize {
        guard args.count >= 6, let side = Int(args[5]), side > 0 else { return Thumbnail.captureSize }
        return CGSize(width: side, height: side)
    }

    /// Entry point for `--capture type subtype manufacturer out.png [longest side]`. Exit code 0 means a PNG was written.
    static func run(_ args: [String]) -> Never {
        alarm(Helper.timeLimit)
        guard args.count >= 5, let type = UInt32(args[1]), let sub = UInt32(args[2]), let man = UInt32(args[3]) else { _exit(1) }
        let out = URL(fileURLWithPath: args[4])
        size = box(args)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        var description = AudioComponentDescription(componentType: type, componentSubType: sub,
                                                    componentManufacturer: man, componentFlags: 0, componentFlagsMask: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { _exit(5) }

        // Like a regular host, create v2 units synchronously on the main thread: frameworks such as
        // JUCE bind their message thread at creation and refuse to build an editor from elsewhere.
        var instance: AudioComponentInstance?
        if let component = AudioComponentFindNext(nil, &description),
           AudioComponentInstanceNew(component, &instance) == noErr, let unit = instance {
            AudioUnitInitialize(unit)
            if let first = cocoaView(unit) {
                // Warm-up: one-time welcome hints (FabFilter and others) go to the first editor that opens,
                // so close it like a host would and capture a fresh one
                show(first)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    first.removeFromSuperview()
                    window?.orderOut(nil)
                    let view = cocoaView(unit) ?? first
                    show(view)
                    attempt(view, to: out, tries: 4)
                }
                app.run()
            }
        }

        // AUv3 and units without a Cocoa editor
        AVAudioUnit.instantiate(with: description, options: []) { unit, _ in
            DispatchQueue.main.async {
                guard let unit = unit else { _exit(2) }
                try? unit.auAudioUnit.allocateRenderResources()
                requestView(unit) { view in
                    guard let view = view else { _exit(3) }
                    show(view)
                    attempt(view, to: out, tries: 4)
                }
            }
        }
        app.run()
        _exit(0)
    }

    /// Plugins draw their first frames at different speeds: retry until the capture isn't blank.
    private static func attempt(_ view: NSView, to out: URL, tries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // _exit skips plugin destructors, some of which abort when torn down outside a real host
            if let png = snapshot(view), (try? png.write(to: out, options: .atomic)) != nil { _exit(0) }
            if tries <= 1 { _exit(4) }
            attempt(view, to: out, tries: tries - 1)
        }
    }

    private static func requestView(_ unit: AVAudioUnit, completion: @escaping (NSView?) -> Void) {
        unit.auAudioUnit.requestViewController { controller in
            DispatchQueue.main.async {
                guard let controller = controller else { completion(nil); return }
                viewController = controller
                let view = controller.view
                if view.frame.size == .zero {
                    let preferred = controller.preferredContentSize
                    view.setFrameSize(preferred == .zero ? NSSize(width: 800, height: 500) : preferred)
                }
                completion(view)
            }
        }
    }

    /// Classic AUv2 editor: the plugin names a bundle and a factory class conforming to AUCocoaUIBase.
    private static func cocoaView(_ unit: AudioUnit) -> NSView? {
        var size: UInt32 = 0
        var writable: DarwinBoolean = false
        guard AudioUnitGetPropertyInfo(unit, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, &size, &writable) == noErr,
              size >= UInt32(MemoryLayout<AudioUnitCocoaViewInfo>.size) else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioUnitCocoaViewInfo>.alignment)
        defer { raw.deallocate() }
        guard AudioUnitGetProperty(unit, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, raw, &size) == noErr else { return nil }

        let info = raw.assumingMemoryBound(to: AudioUnitCocoaViewInfo.self).pointee
        let bundleURL = info.mCocoaAUViewBundleLocation.takeUnretainedValue() as URL
        let className = info.mCocoaAUViewClass.takeUnretainedValue() as String
        guard let bundle = Bundle(url: bundleURL), bundle.load(),
              let factoryClass = bundle.classNamed(className) as? NSObject.Type else { return nil }

        // AUCocoaUIBase lives in a header Swift doesn't import, so call the selector directly
        let factory = factoryClass.init()
        let selector = NSSelectorFromString("uiViewForAudioUnit:withSize:")
        guard factory.responds(to: selector) else { return nil }
        typealias Factory = @convention(c) (AnyObject, Selector, AudioUnit, NSSize) -> Unmanaged<NSView>?
        let make = unsafeBitCast(factory.method(for: selector), to: Factory.self)
        return make(factory, selector, unit, NSSize(width: 800, height: 500))?.takeUnretainedValue()
    }

    private static func show(_ view: NSView) {
        let size = view.frame.size == .zero ? NSSize(width: 800, height: 500) : view.frame.size
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // JUCE and similar frameworks stop painting while a window is occluded, so keep it on top
        window.level = .floating
        // Hosts embed the editor in their own container; wrappers build the real editor when it gets a superview
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        window.contentView = container
        view.setFrameOrigin(.zero)
        container.addSubview(view)
        if let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 24, y: screen.visibleFrame.minY + 24))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        self.window = window
    }

    /// Captures the helper's own window, which needs no Screen Recording permission.
    /// Falls back to drawing the view for plugins that render without a window server image.
    private static func snapshot(_ view: NSView) -> Data? {
        if let window = window,
           let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                                               [.boundsIgnoreFraming, .bestResolution]),
           !Thumbnail.isBlank(image) {
            return Thumbnail.png(image, fitting: size)
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let image = rep.cgImage, !Thumbnail.isBlank(image) else { return nil }
        return Thumbnail.png(image, fitting: size)
    }
}
