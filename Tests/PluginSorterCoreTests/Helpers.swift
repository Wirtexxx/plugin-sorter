import Foundation

/// A fresh folder under $TMPDIR, removed when the value goes away.
final class TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("ps-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func path(_ relative: String) -> URL { url.appendingPathComponent(relative) }

    func exists(_ relative: String) -> Bool { FileManager.default.fileExists(atPath: path(relative).path) }
}

/// Writes .fst presets the way FL Studio does: an FLhd header followed by an FLdt event stream.
enum FSTBuilder {
    static func make(display: String? = nil, name: String? = nil, vendor: String? = nil, path: String? = nil,
                     padding: Bool = true) -> Data {
        var events = Data()
        if padding {
            events.append(contentsOf: [0x1C, 0x01])                    // byte event
            events.append(contentsOf: [0x41, 0x34, 0x12])              // word event
            events.append(contentsOf: [0x99, 0x01, 0x02, 0x03, 0x04])  // dword event
            events.append(text(199, Data("11.5.5\0".utf8)))           // FL version, plain text
        }
        if let display = display {
            var utf16 = Data()
            for unit in (display + "\0").utf16 { utf16.append(contentsOf: [UInt8(unit & 0xFF), UInt8(unit >> 8)]) }
            events.append(text(203, utf16))
        }
        var records = Data(le32(8))
        for (id, value) in [(51, path), (54, name), (56, vendor)] {
            guard let value = value else { continue }
            let bytes = Data(value.utf8)
            records.append(le32(UInt32(id)))
            records.append(le64(UInt64(bytes.count)))
            records.append(bytes)
        }
        events.append(text(213, records))

        var file = Data("FLhd".utf8)
        file.append(le32(6))
        file.append(contentsOf: [0x30, 0x00, 0x02, 0x00, 0x30, 0x00])
        file.append(Data("FLdt".utf8))
        file.append(le32(UInt32(events.count)))
        file.append(events)
        return file
    }

    /// Variable-length event: id, LEB128 length, payload.
    static func text(_ id: UInt8, _ payload: Data) -> Data {
        var out = Data([id])
        var length = payload.count
        repeat {
            var byte = UInt8(length & 0x7F)
            length >>= 7
            if length > 0 { byte |= 0x80 }
            out.append(byte)
        } while length > 0
        out.append(payload)
        return out
    }

    static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    static func le64(_ v: UInt64) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
}

/// Minimal Mach-O headers, enough for PluginInventory.archs.
enum MachO {
    static let x86_64: UInt32 = 0x0100_0007
    static let arm64: UInt32 = 0x0100_000C
    static let i386: UInt32 = 7

    static func fat(_ cpus: [UInt32]) -> Data {
        var data = be32(0xCAFE_BABE) + be32(UInt32(cpus.count))
        for cpu in cpus { data += be32(cpu) + Data(count: 16) }
        return data + Data(count: 64)
    }

    static func thin(_ cpu: UInt32) -> Data {
        let magic: UInt32 = cpu == i386 ? 0xFEED_FACE : 0xFEED_FACF
        return withUnsafeBytes(of: magic.littleEndian) { Data($0) } + withUnsafeBytes(of: cpu.littleEndian) { Data($0) }
            + Data(count: 64)
    }

    private static func be32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
}

/// Creates a fake plugin bundle: Contents/Info.plist and, unless `binary` is nil, Contents/MacOS/<name>.
@discardableResult
func makeBundle(_ url: URL, id: String? = nil, version: String = "1.0", binary: Data? = MachO.fat([MachO.x86_64, MachO.arm64]),
                extra: [String: Any] = [:]) throws -> URL {
    let contents = url.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
    let executable = url.deletingPathExtension().lastPathComponent
    var info: [String: Any] = ["CFBundleExecutable": executable, "CFBundleShortVersionString": version]
    if let id = id { info["CFBundleIdentifier"] = id }
    info.merge(extra) { $1 }
    let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try plist.write(to: contents.appendingPathComponent("Info.plist"))
    if let binary = binary {
        try binary.write(to: contents.appendingPathComponent("MacOS/\(executable)"))
    }
    return url
}

/// Lets the main queue run until `condition` holds.
@MainActor func wait(until condition: @escaping () -> Bool) async {
    for _ in 0..<1000 where !condition() { try? await Task.sleep(nanoseconds: 2_000_000) }
}
