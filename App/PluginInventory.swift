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

    var displayPath: String { url.path.replacingOccurrences(of: PluginInventory.root.path + "/", with: "") }
}

/// A plugin with all its formats, e.g. Pro-Q 4 as VST3 + AU + CLAP.
struct ManagedPlugin: Identifiable {
    var id: String { key }
    let key: String
    let name: String
    let vendor: String
    let bundles: [PluginBundle]

    var version: String { bundles.lazy.map(\.version).first { !$0.isEmpty } ?? "" }
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

    static func scan() -> [ManagedPlugin] {
        var bundles: [PluginBundle] = []
        for format in PluginFormat.allCases {
            let dir = root.appendingPathComponent(format.folder, isDirectory: true)
            guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in walker where url.pathExtension.lowercased() == format.fileExtension {
                walker.skipDescendants()
                bundles.append(read(url, format: format, formatRoot: dir))
            }
        }

        // Formats of one plugin share a file name: "FabFilter Pro-Q 4.vst3" and "FabFilter Pro-Q 4.component"
        let grouped = Dictionary(grouping: bundles) { key(for: $0.url) }
        return grouped.map { key, items in
            let sorted = items.sorted { $0.format.rawValue < $1.format.rawValue }
            let name = sorted.map { $0.url.deletingPathExtension().lastPathComponent }.min { $0.count < $1.count } ?? key
            return ManagedPlugin(key: key, name: name,
                                 vendor: sorted.lazy.map(\.vendor).first { !$0.isEmpty } ?? "",
                                 bundles: sorted)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Lowercase letters and digits of the file name, minus suffixes some vendors add to the AU ("ValhallaRoomAU64").
    private static func key(for url: URL) -> String {
        var key = url.deletingPathExtension().lastPathComponent.lowercased().filter { $0.isLetter || $0.isNumber }
        for suffix in ["au64", "au"] where key.hasSuffix(suffix) && key.count > suffix.count + 2 {
            key.removeLast(suffix.count)
            break
        }
        return key
    }

    private static func read(_ url: URL, format: PluginFormat, formatRoot: URL) -> PluginBundle {
        let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        let parent = url.deletingLastPathComponent()
        let nested = parent.standardizedFileURL.path != formatRoot.standardizedFileURL.path

        var vendor = nested ? parent.lastPathComponent : ""
        var au: AUCode?
        if format == .au, let component = (info["AudioComponents"] as? [[String: Any]])?.first {
            if vendor.isEmpty, let name = component["name"] as? String, let colon = name.range(of: ": ") {
                vendor = String(name[..<colon.lowerBound])
            }
            if let type = component["type"] as? String, let subtype = component["subtype"] as? String,
               let manufacturer = component["manufacturer"] as? String {
                au = AUCode(type: type, subtype: subtype, manufacturer: manufacturer)
            }
        }
        if vendor.isEmpty, let id = info["CFBundleIdentifier"] as? String {
            let skip: Set<String> = ["com", "co", "uk", "net", "org", "io", "app", "audio", "de", "fr"]
            vendor = id.split(separator: ".").map(String.init).first { !skip.contains($0.lowercased()) } ?? ""
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
                            au: au, nested: nested)
    }

    /// CPU architectures from the Mach-O header, universal or thin.
    static func archs(_ executable: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: executable) else { return [] }
        defer { try? handle.close() }
        let b = [UInt8](handle.readData(ofLength: 4096))
        guard b.count >= 8 else { return [] }
        func be(_ i: Int) -> UInt32 { b[i..<i + 4].reduce(0) { $0 << 8 | UInt32($1) } }
        func le(_ i: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(b[i + $1]) << (8 * UInt32($1)) } }

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
