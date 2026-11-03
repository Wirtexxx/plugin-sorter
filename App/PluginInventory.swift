import Foundation

enum PluginFormat: String, CaseIterable {
    case vst3 = "VST3", vst = "VST", au = "AU", clap = "CLAP"

    var folder: String {
        switch self {
        case .vst3: return "VST3"
        case .vst:  return "VST"
        case .au:   return "Components"
        case .clap: return "CLAP"
        }
    }

    var fileExtension: String {
        switch self {
        case .vst3: return "vst3"
        case .vst:  return "vst"
        case .au:   return "component"
        case .clap: return "clap"
        }
    }
}

/// Four-character codes that identify an Audio Unit, as `auval` expects them.
struct AUCode: Equatable {
    let type: String
    let subtype: String
    let manufacturer: String
}

/// One plugin file on disk, e.g. FabFilter Pro-Q 4.vst3.
struct PluginBundle: Identifiable {
    var id: String { url.path }
    let url: URL
    let format: PluginFormat
    let vendor: String
    let version: String
    let executable: URL?
    let archs: [String]
    let quarantined: Bool
    let au: AUCode?
    /// Inside a vendor folder rather than directly in the format folder.
    let nested: Bool
    /// Developer part of the bundle identifier ("fabfilter" in com.fabfilter.Pro-Q.4), used to keep
    /// same-named plugins of different developers apart.
    var idVendor = ""
    /// An Audio Unit's own name, without the developer ("Ozone 11 Clarity" in "iZotope: Ozone 11 Clarity").
    var auName = ""
    /// Turned off: moved to Disabled/ in the plugin tree, where no host looks.
    var isDisabled = false
    /// CFBundleIdentifier, the key of the plugin's preferences and caches.
    var bundleID = ""

    /// Where the file goes when it is turned on again: the same path without "Disabled/".
    var enabledURL: URL {
        guard isDisabled else { return url }
        var parts = url.pathComponents
        if let index = parts.indices.dropLast().last(where: {
            parts[$0] == PluginInventory.disabledFolder && parts[$0 + 1] == format.folder
        }) {
            parts.remove(at: index)
        }
        return URL(fileURLWithPath: NSString.path(withComponents: parts))
    }

    /// Path from the format folder on, e.g. "VST3/FabFilter/FabFilter Pro-Q 4.vst3".
    var displayPath: String {
        let parts = url.pathComponents
        guard let start = parts.lastIndex(of: format.folder) else { return url.path }
        return parts[start...].joined(separator: "/")
    }
}

/// A plugin with all its formats, e.g. Pro-Q 4 as VST3 + AU + CLAP.
struct ManagedPlugin: Identifiable {
    var id: String { key }
    let key: String
    let name: String
    let vendor: String
    let bundles: [PluginBundle]

    var version: String { bundles.lazy.map(\.version).first { !$0.isEmpty } ?? "" }
    /// Every file is turned off. A plugin with one format still on counts as on.
    var isDisabled: Bool { !bundles.isEmpty && bundles.allSatisfy(\.isDisabled) }
    /// The files hosts can see: the only ones worth checking and registering.
    var activeBundles: [PluginBundle] { bundles.filter { !$0.isDisabled } }
}

enum PluginInventory {
    static let root = URL(fileURLWithPath: "/Library/Audio/Plug-Ins", isDirectory: true)

    static var hostArch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    /// Where turned-off plugins live inside the plugin tree, mirroring the format folders.
    static let disabledFolder = "Disabled"

    static func scan(root: URL = PluginInventory.root) -> [ManagedPlugin] {
        var bundles: [PluginBundle] = []
        let disabledRoot = root.appendingPathComponent(disabledFolder, isDirectory: true)
        for format in PluginFormat.allCases {
            for (base, isDisabled) in [(root, false), (disabledRoot, true)] {
                let dir = base.appendingPathComponent(format.folder, isDirectory: true)
                guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles]) else { continue }
                for case let url as URL in walker where url.pathExtension.lowercased() == format.fileExtension {
                    walker.skipDescendants()
                    var bundle = read(url, format: format, formatRoot: dir)
                    bundle.isDisabled = isDisabled
                    bundles.append(bundle)
                }
            }
        }

        // Formats of one plugin share a file name: "FabFilter Pro-Q 4.vst3" and "FabFilter Pro-Q 4.component"
        // …and a developer: two "Compressor"s from different developers must never become one row
        var keys = bundles.map { key(for: $0.url) + "|" + $0.idVendor }
        // Some AUs have a file name unlike the plugin's ("iZOzone11ClarityAUHook"): join those by the AU's own name
        let counts = Dictionary(keys.map { ($0, 1) }, uniquingKeysWith: +)
        for (n, bundle) in bundles.enumerated() where bundle.format == .au && !bundle.auName.isEmpty && counts[keys[n]] == 1 {
            let named = key(for: URL(fileURLWithPath: bundle.auName)) + "|" + bundle.idVendor
            if counts[named] != nil { keys[n] = named }
        }
        let grouped = Dictionary(grouping: bundles.indices) { keys[$0] }.mapValues { $0.map { bundles[$0] } }
        return grouped.map { key, items in
            let sorted = items.sorted { $0.format.rawValue < $1.format.rawValue }
            let names: [String] = sorted.map { $0.url.deletingPathExtension().lastPathComponent }
            let name: String = names.min { $0.count < $1.count } ?? key
            // Best vendor name first: a vendor folder (already pretty), then the AU's "Vendor: Name",
            // then whatever the bundle id gives
            let named: [PluginBundle] = sorted.filter { !$0.vendor.isEmpty }
            let best: PluginBundle? = named.first(where: \.nested) ?? named.first { $0.format == .au } ?? named.first
            let vendor: String = best?.vendor ?? ""
            return ManagedPlugin(key: key, name: name, vendor: vendor, bundles: sorted)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Lowercase letters and digits of the file name, minus the suffix some vendors add to the AU
    /// ("ValhallaRoomAU64"). Only an uppercase AU counts, so "Plateau" stays "plateau".
    static func key(for url: URL) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        for suffix in ["AU64", "AU"] where name.hasSuffix(suffix) && name.count > suffix.count + 2 {
            name.removeLast(suffix.count)
            break
        }
        return name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func read(_ url: URL, format: PluginFormat, formatRoot: URL) -> PluginBundle {
        let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        let parent = url.deletingLastPathComponent()
        let nested = parent.standardizedFileURL.path != formatRoot.standardizedFileURL.path

        var vendor = nested ? parent.lastPathComponent : ""
        var au: AUCode?
        var auName = ""
        if format == .au, let component = (info["AudioComponents"] as? [[String: Any]])?.first {
            if let name = component["name"] as? String {
                let colon = name.range(of: ": ")
                auName = colon.map { String(name[$0.upperBound...]) } ?? name
                if vendor.isEmpty, let colon = colon { vendor = String(name[..<colon.lowerBound]) }
            }
            if let type = component["type"] as? String, let subtype = component["subtype"] as? String,
               let manufacturer = component["manufacturer"] as? String {
                au = AUCode(type: type, subtype: subtype, manufacturer: manufacturer)
            }
        }
        let identifier = info["CFBundleIdentifier"] as? String
        if vendor.isEmpty, let id = identifier {
            vendor = id.split(separator: ".").map(String.init).first { !domainParts.contains($0.lowercased()) } ?? ""
        }

        let executable = (info["CFBundleExecutable"] as? String).map {
            url.appendingPathComponent("Contents/MacOS", isDirectory: true).appendingPathComponent($0)
        }
        let exists = executable.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let version = (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String) ?? ""

        return PluginBundle(url: url, format: format, vendor: vendor, version: version,
                            executable: exists ? executable : nil,
                            archs: exists ? executable.map(archs) ?? [] : [],
                            quarantined: getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0,
                            au: au, nested: nested, idVendor: idVendor(identifier), auName: auName,
                            bundleID: identifier ?? "")
    }

    /// Domain parts skipped to find the developer in a bundle id; keep in sync with vendor_from_id in the script.
    static let domainParts: Set<String> = ["com", "co", "uk", "net", "org", "io", "app", "audio",
                                           "de", "fr", "nl", "se", "dk", "ch", "at", "it", "jp", "au", "ca", "us"]

    /// "com.fabfilter.Pro-Q.4" → "fabfilter", "co.uk.gvst.GClip" → "gvst".
    static func idVendor(_ identifier: String?) -> String {
        guard let identifier = identifier else { return "" }
        let part = identifier.split(separator: ".").map(String.init).first { !domainParts.contains($0.lowercased()) }
        return (part ?? "").lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// CPU architectures from the Mach-O header, universal or thin.
    static func archs(_ executable: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: executable) else { return [] }
        defer { try? handle.close() }
        let b = [UInt8](handle.readData(ofLength: 4096))
        guard b.count >= 8 else { return [] }
        func be(_ i: Int) -> UInt32 {
            var value: UInt32 = 0
            for n in 0..<4 { value = (value << 8) | UInt32(b[i + n]) }
            return value
        }
        func le(_ i: Int) -> UInt32 {
            var value: UInt32 = 0
            for n in 0..<4 { value |= UInt32(b[i + n]) << UInt32(8 * n) }
            return value
        }

        switch be(0) {
        case 0xCAFE_BABE, 0xCAFE_BABF:
            let stride = be(0) == 0xCAFE_BABF ? 32 : 20
            return (0..<Int(be(4))).compactMap { n in
                let offset = 8 + n * stride
                return offset + 4 <= b.count ? cpuName(be(offset)) : nil
            }
        case 0xCFFA_EDFE, 0xCEFA_EDFE:
            return [cpuName(le(4))].compactMap { $0 }
        default:
            return []
        }
    }

    private static func cpuName(_ type: UInt32) -> String? {
        switch type {
        case 0x0100_0007: return "x86_64"
        case 0x0100_000C: return "arm64"
        case 7:           return "i386"
        default:          return nil
        }
    }
}
