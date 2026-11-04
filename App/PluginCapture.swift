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
}
