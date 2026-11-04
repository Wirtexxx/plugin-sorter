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
        var value: UInt32 = 0
        for n in 0..<4 { value |= UInt32(b[i + n]) << UInt32(8 * n) }
        return value
    }

    private static func u64(_ b: [UInt8], _ i: Int) -> UInt64 {
        var value: UInt64 = 0
        for n in 0..<8 { value |= UInt64(b[i + n]) << UInt64(8 * n) }
        return value
    }

    private static func utf16(_ bytes: [UInt8]) -> String {
        var units: [UInt16] = []
        for i in stride(from: 0, to: bytes.count - 1, by: 2) {
            let low = UInt16(bytes[i])
            let high = UInt16(bytes[i + 1]) << 8
            units.append(low | high)
        }
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
        /// The .nfo's exact bytes before we touched it; nil when it didn't exist.
        var originalNfoData: Data?
        /// Older manifests kept the .nfo as text; still read so their pictures can be removed.
        var originalNfo: String?
    }

    private(set) var records: [String: Record] = [:]
    private let store: JSONStore<[String: Record]>

    static let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Plugin Sorter/fl-pictures.json")

    init(url: URL = PictureManifest.defaultURL) {
        store = JSONStore(url: url, pretty: true)
        records = store.load() ?? [:]
    }

    /// The one the app uses: the pictures and the favourites both change it, from their own queues.
    static let shared = PictureManifest()

    private let lock = NSLock()

    subscript(picture: URL) -> Record? {
        lock.lock()
        defer { lock.unlock() }
        return records[Self.key(picture)]
    }

    /// Nil forgets the picture. A record that can't be saved isn't kept: the way back must be on disk.
    func set(_ record: Record?, for picture: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        var next = records
        next[Self.key(picture)] = record
        try store.save(next)
        records = next
    }

    /// Follows a picture that moved with its favourite into another folder.
    func move(_ picture: URL, to destination: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        var next = records
        guard let record = next.removeValue(forKey: Self.key(picture)) else { return }
        next[Self.key(destination)] = record
        try store.save(next)
        records = next
    }

    /// The same file can be reached through a symlinked folder (/var vs /private/var, a linked Documents),
    /// so records are keyed by the folder with links resolved. The picture itself may not exist yet.
    private static func key(_ picture: URL) -> String {
        picture.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(picture.lastPathComponent).path
    }
}

enum FLDatabase {
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/Image-Line/FL Studio/Presets/Plugin database", isDirectory: true)

    static var exists: Bool { FileManager.default.fileExists(atPath: root.path) }

    /// Every favourite in Effects and Generators, including category subfolders.
    static func scan(_ manifest: PictureManifest, root: URL = FLDatabase.root) -> [FLPlugin] {
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
        // Work on bytes: FL's files aren't always UTF-8, and String I/O can also drop a BOM.
        // Only the Bitmap= line changes, and it moves to the end.
        let original = try? Data(contentsOf: plugin.nfo)
        let previous = manifest[plugin.picture]
        var record = PictureManifest.Record(source: source, originalNfoData: original, originalNfo: nil)
        if let previous = previous {
            // A second write keeps what was there before the first one
            record.originalNfoData = previous.originalNfoData
            record.originalNfo = previous.originalNfo
        }
        // The way back first: FL's files change only once it's on disk
        try manifest.set(record, for: plugin.picture)
        do {
            try png.write(to: plugin.picture, options: .atomic)
            try nfoPointing(at: plugin.picture.lastPathComponent, from: original).write(to: plugin.nfo, options: .atomic)
        } catch {
            try? manifest.set(previous, for: plugin.picture)
            throw error
        }
    }

    /// "Bitmap=…" in any letter case, compared as ASCII bytes.
    private static func isBitmapLine(_ line: [UInt8]) -> Bool {
        let prefix: [UInt8] = Array("bitmap=".utf8)
        guard line.count >= prefix.count else { return false }
        for i in 0..<prefix.count {
            let byte: UInt8 = line[i] >= 0x41 && line[i] <= 0x5A ? line[i] + 0x20 : line[i]
            if byte != prefix[i] { return false }
        }
        return true
    }

    /// The .nfo with its Bitmap= line last, keeping the BOM, the line endings and the other lines as they
    /// are. Empty lines and a final line break don't survive.
    static func nfoPointing(at picture: String, from original: Data?) -> Data {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        var bytes = [UInt8](original ?? Data())
        let hadBOM = bytes.starts(with: bom)
        if hadBOM { bytes.removeFirst(bom.count) }
        var crlf = false
        for i in bytes.indices.dropLast() where bytes[i] == 0x0D && bytes[i + 1] == 0x0A {
            crlf = true
            break
        }

        var lines: [[UInt8]] = []
        for slice in bytes.split(separator: 0x0A, omittingEmptySubsequences: true) {
            var line = Array(slice)
            if line.last == 0x0D { line.removeLast() }
            if !line.isEmpty && !isBitmapLine(line) { lines.append(line) }
        }
        lines.append(Array("Bitmap=\(picture)".utf8))

        let newline: [UInt8] = crlf ? [0x0D, 0x0A] : [0x0A]
        var out = hadBOM ? bom : []
        for (n, line) in lines.enumerated() {
            if n > 0 { out += newline }
            out += line
        }
        return Data(out)
    }

    /// Deletes a picture added by Plugin Sorter and restores the original .nfo. The record goes last: as
    /// long as the .nfo isn't back, it is the only copy of what was there.
    static func remove(_ plugin: FLPlugin, manifest: PictureManifest) throws {
        guard let record = manifest[plugin.picture] else { return }
        let fm = FileManager.default
        if let original = record.originalNfoData {
            try original.write(to: plugin.nfo, options: .atomic)
        } else if let legacy = record.originalNfo {
            try Data(legacy.utf8).write(to: plugin.nfo, options: .atomic)
        } else if fm.fileExists(atPath: plugin.nfo.path) {
            try fm.removeItem(at: plugin.nfo)
        }
        if fm.fileExists(atPath: plugin.picture.path) { try fm.removeItem(at: plugin.picture) }
        try manifest.set(nil, for: plugin.picture)
    }
}
