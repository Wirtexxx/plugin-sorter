import Foundation

/// One value in one JSON file. Nothing here hides a problem: a file that can't be read is kept next to
/// the original as `.bad` instead of being overwritten by the next save, and a failed save throws.
struct JSONStore<Value: Codable> {
    let url: URL
    var pretty = false

    /// Nil when there is no file, or it couldn't be read and was put aside.
    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let value = try? JSONDecoder().decode(Value.self, from: data) { return value }
        let bad = url.appendingPathExtension("bad")
        try? FileManager.default.removeItem(at: bad)
        try? FileManager.default.moveItem(at: url, to: bad)
        return nil
    }

    func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
