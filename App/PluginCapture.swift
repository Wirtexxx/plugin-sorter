import AppKit
import AVFoundation
import AudioToolbox
import CoreAudioKit

/// Takes a screenshot of a plugin's interface through its Audio Unit version.
///
/// Every capture runs in a separate copy of the app (`--capture`), so a plugin that
/// crashes or hangs only takes down that helper, never the main window.
enum PluginCapture {
    static func components() -> [AVAudioUnitComponent] {
        AVAudioUnitComponentManager.shared().components { _, _ in true }
    }

    /// Finds the AU for an FL entry by plugin name, preferring the same developer.
    static func match(_ plugin: FLPlugin, in components: [AVAudioUnitComponent]) -> AVAudioUnitComponent? {
        let names = Set([plugin.info.name, plugin.title].map(normalize).filter { !$0.isEmpty })
        let vendor = normalize(plugin.info.vendor)
        let candidates = components.filter { names.contains(normalize($0.name)) }
        return candidates.first { vendor.isEmpty || normalize($0.manufacturerName) == vendor }
            ?? (candidates.count == 1 ? candidates[0] : nil)
    }

    /// Finds the AU of an installed plugin: by its code, or by name as with FL's favourites.
    static func match(_ plugin: ManagedPlugin, in components: [AVAudioUnitComponent]) -> AVAudioUnitComponent? {
        let bundles = plugin.activeBundles.filter { $0.format == .au }
        for code in bundles.compactMap(\.au) {
            let found = components.first {
                let d = $0.audioComponentDescription
                return fourCC(d.componentSubType) == code.subtype && fourCC(d.componentManufacturer) == code.manufacturer
            }
            if let found = found { return found }
        }
        let names = Set(([plugin.name] + bundles.map(\.auName)).map(normalize).filter { !$0.isEmpty })
        let vendor = normalize(plugin.vendor)
        let candidates = components.filter { names.contains(normalize($0.name)) }
        return candidates.first { normalize($0.manufacturerName) == vendor } ?? (candidates.count == 1 ? candidates[0] : nil)
    }

    /// Audio Unit codes are Mac Roman, not UTF-8: "©abc" is a real manufacturer code.
    static func fourCC(_ code: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .macOSRoman) ?? ""
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Returns a thumbnail PNG, or nil if the plugin couldn't be shown or captured in time.
    static func capture(_ component: AVAudioUnitComponent, timeout: TimeInterval = 25) -> Data? {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: out) }

        let d = component.audioComponentDescription
        guard let helper = Helper.process(["--capture", "\(d.componentType)", "\(d.componentSubType)",
                                           "\(d.componentManufacturer)", out.path]) else { return nil }
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        let ended = DispatchSemaphore(value: 0)
        helper.terminationHandler = { _ in ended.signal() }
        guard (try? helper.run()) != nil else { return nil }
        if ended.wait(timeout: .now() + timeout) == .timedOut { kill(helper.processIdentifier, SIGKILL) }
        helper.waitUntilExit()
        // The helper only writes the file after a successful capture, so its presence is the result
        guard let png = try? Data(contentsOf: out), !png.isEmpty else { return nil }
        return png
    }

    // MARK: - Helper process

    private static var window: NSWindow?
    private static var viewController: NSViewController?

    /// Entry point for `--capture type subtype manufacturer out.png`. Exit code 0 means a PNG was written.
    static func runHelper(_ args: [String]) -> Never {
        alarm(Helper.timeLimit)
        guard args.count >= 5, let type = UInt32(args[1]), let sub = UInt32(args[2]), let man = UInt32(args[3]) else { _exit(1) }
        let out = URL(fileURLWithPath: args[4])
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
            return Thumbnail.png(image, fitting: Thumbnail.captureSize)
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let image = rep.cgImage, !Thumbnail.isBlank(image) else { return nil }
        return Thumbnail.png(image, fitting: Thumbnail.captureSize)
    }
}
