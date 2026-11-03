import Foundation

/// Check results kept between launches, so the list shows each plugin's state as soon as it opens.
/// A result counts only while the bundle is unchanged: an updated plugin is checked again.
final class CheckCache {
    private struct Record: Codable {
        let modified: Date
        let issues: [Issue]
    }

    static let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Plugin Sorter/checks.json")

    private var records: [String: Record] = [:]
    private let url: URL
    private let lock = NSLock()

    init(url: URL = CheckCache.defaultURL) {
        self.url = url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = saved
        }
    }

    /// The saved result, nil when the bundle was never checked or changed since.
    func issues(for bundle: PluginBundle) -> [Issue]? {
        lock.lock()
        defer { lock.unlock() }
        guard let record = records[bundle.url.path], record.modified == Self.modified(bundle.url) else { return nil }
        return record.issues
    }

    func store(_ issues: [Issue], for bundle: PluginBundle) {
        lock.lock()
        defer { lock.unlock() }
        records[bundle.url.path] = Record(modified: Self.modified(bundle.url), issues: issues)
        save()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        records = [:]
        save()
    }

    /// Bundles the background check still has to look at: never checked, changed since, and not on their way out.
    static func pending(_ bundles: [PluginBundle], cache: CheckCache, forgotten: Set<String>) -> [PluginBundle] {
        bundles.filter { !forgotten.contains($0.id) && cache.issues(for: $0) == nil }
    }

    private func save() {
        try? JSONEncoder().encode(records).write(to: url, options: .atomic)
    }

    private static func modified(_ url: URL) -> Date {
        // Not URL.resourceValues: a URL caches them, so a plugin updated in place would look unchanged
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
    }
}
