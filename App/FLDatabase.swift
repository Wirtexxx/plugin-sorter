import Foundation

/// Plugin facts stored in an FL Studio .fst preset.
struct FSTInfo {
    var name = ""
    var vendor = ""
    var path = ""
}

/// Minimal reader for FL Studio's event format (FLhd header + FLdt event stream).
enum FST {
    private static let displayName: UInt8 = 203
    private static let pluginData: UInt8 = 213

    static func read(_ url: URL) -> FSTInfo? {
        guard let data = try? Data(contentsOf: url), data.count > 22 else { return nil }
        let b = [UInt8](data)
        guard b[0..<4].elementsEqual("FLhd".utf8) else { return nil }
        var i = 8 + Int(u32(b, 4))
        guard i + 8 <= b.count, b[i..<i + 4].elementsEqual("FLdt".utf8) else { return nil }
        i += 8

        var info = FSTInfo()
        var display = ""
        while i < b.count {
            let id = b[i]
            i += 1
            // Event size is encoded in the id range: byte, word, dword, then variable-length data
            if id < 64 { i += 1; continue }
            if id < 128 { i += 2; continue }
            if id < 192 { i += 4; continue }
            var length = 0
            var shift = 0
            while i < b.count, shift < 28 {
                let byte = b[i]
                i += 1
                length |= Int(byte & 0x7F) << shift
                shift += 7
                if byte & 0x80 == 0 { break }
            }
            guard i + length <= b.count else { break }
            let payload = Array(b[i..<i + length])
            i += length
            if id == displayName && display.isEmpty { display = utf16(payload) }
            if id == pluginData { records(payload, into: &info) }
        }
        if info.name.isEmpty { info.name = display }
        return info
    }

    /// Plugin data: a u32 header, then records of u32 id + u64 length + bytes.
    private static func records(_ p: [UInt8], into info: inout FSTInfo) {
        var i = 4
        while i + 12 <= p.count {
            let id = u32(p, i)
            let length = u64(p, i + 4)
            i += 12
            guard length <= UInt64(p.count - i) else { return }
            let end = i + Int(length)
            let text = String(decoding: p[i..<end], as: UTF8.self)
                .trimmingCharacters(in: CharacterSet.controlCharacters.union(.whitespaces))
            switch id {
            case 51: info.path = text
            case 54: info.name = text
            case 56: info.vendor = text
            default: break
            }
            i = end
        }
    }

    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(b[i + $1]) << (8 * UInt32($1)) }
    }

    private static func u64(_ b: [UInt8], _ i: Int) -> UInt64 {
        (0..<8).reduce(0) { $0 | UInt64(b[i + $1]) << (8 * UInt64($1)) }
    }

    private static func utf16(_ bytes: [UInt8]) -> String {
        let units = stride(from: 0, to: bytes.count - 1, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }
        return String(decoding: units, as: UTF16.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }
}

struct FLPlugin: Identifiable {
    enum Source: String, Codable { case screenshot, card, custom }

    var id: String { fst.path }
    let fst: URL
    /// Name as FL shows it in the browser (the preset file name).
    let title: String
    let info: FSTInfo
    let hasPicture: Bool
    /// Set when the picture was added by Plugin Sorter; nil with a picture means FL's own.
    let source: Source?

    var picture: URL { fst.deletingPathExtension().appendingPathExtension("png") }
    var nfo: URL { fst.deletingPathExtension().appendingPathExtension("nfo") }
    var isStock: Bool { hasPicture && source == nil }
}

/// Remembers what Plugin Sorter wrote so it can be removed cleanly.
final class PictureManifest {
    struct Record: Codable {
        var source: FLPlugin.Source
        /// Contents of the .nfo before we touched it; nil when it didn't exist.
        var originalNfo: String?
    }

    private(set) var records: [String: Record] = [:]
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Plugin Sorter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("fl-pictures.json")
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = saved
        }
    }

    subscript(picture: URL) -> Record? {
        get { records[picture.path] }
        set { records[picture.path] = newValue; save() }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(records).write(to: url, options: .atomic)
    }
}

enum FLDatabase {
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/Image-Line/FL Studio/Presets/Plugin database", isDirectory: true)

    static var exists: Bool { FileManager.default.fileExists(atPath: root.path) }

    /// Every favourite in Effects and Generators, including category subfolders.
    static func scan(_ manifest: PictureManifest) -> [FLPlugin] {
        var plugins: [FLPlugin] = []
        for section in ["Effects", "Generators"] {
            let dir = root.appendingPathComponent(section, isDirectory: true)
            guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension.lowercased() == "fst" {
                // FL's own modules (Audio Clip, Automation Clip…) carry no vendor and aren't plugins
                guard let info = FST.read(url), !info.vendor.isEmpty else { continue }
                let png = url.deletingPathExtension().appendingPathExtension("png")
                plugins.append(FLPlugin(fst: url,
                                        title: url.deletingPathExtension().lastPathComponent,
                                        info: info,
                                        hasPicture: FileManager.default.fileExists(atPath: png.path),
                                        source: manifest[png]?.source))
            }
        }
        return plugins.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Writes Name.png and points Name.nfo at it, the same way FL's stock entries do.
    static func install(_ png: Data, for plugin: FLPlugin, source: FLPlugin.Source, manifest: PictureManifest) throws {
        let original = try? String(contentsOf: plugin.nfo, encoding: .utf8)
        let isFirstWrite = manifest[plugin.picture] == nil
        try png.write(to: plugin.picture, options: .atomic)

        let newline = original?.contains("\r\n") == true ? "\r\n" : "\n"
        var lines = (original ?? "")
            .components(separatedBy: CharacterSet.newlines)
            .filter { !$0.isEmpty && !$0.replacingOccurrences(of: "\u{FEFF}", with: "").lowercased().hasPrefix("bitmap=") }
        lines.append("Bitmap=\(plugin.picture.lastPathComponent)")
        try lines.joined(separator: newline).write(to: plugin.nfo, atomically: true, encoding: .utf8)

        let previous = manifest[plugin.picture]?.originalNfo
        manifest[plugin.picture] = PictureManifest.Record(source: source, originalNfo: isFirstWrite ? original : previous)
    }

    /// Deletes a picture added by Plugin Sorter and restores the original .nfo.
    static func remove(_ plugin: FLPlugin, manifest: PictureManifest) {
        guard let record = manifest[plugin.picture] else { return }
        try? FileManager.default.removeItem(at: plugin.picture)
        if let original = record.originalNfo {
            try? original.write(to: plugin.nfo, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: plugin.nfo)
        }
        manifest[plugin.picture] = nil
    }
}
