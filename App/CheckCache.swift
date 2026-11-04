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
    private let store: JSONStore<[String: Record]>
    private let lock = NSLock()

    init(url: URL = CheckCache.defaultURL) {
        store = JSONStore(url: url)
        records = store.load() ?? [:]
    }

    /// The saved result, nil when the bundle was never checked or changed since.
    func issues(for bundle: PluginBundle) -> [Issue]? {
        lock.lock()
        defer { lock.unlock() }
        guard let record = records[bundle.url.path], record.modified == Self.modified(bundle),
              record.issues.contains(.quarantined) == bundle.quarantined else { return nil }
        return record.issues
    }

    /// Every saved result among these bundles, by id. Reads each bundle's dates, so not for the main thread.
    func saved(for bundles: [PluginBundle]) -> [String: [Issue]] {
        var saved: [String: [Issue]] = [:]
        for bundle in bundles { saved[bundle.id] = issues(for: bundle) }
        return saved
    }

    /// Results that depend on the moment rather than the plugin (a timeout, macOS's AU registry) aren't kept.
    func store(_ issues: [Issue], for bundle: PluginBundle) {
        lock.lock()
        defer { lock.unlock() }
        if issues.contains(where: { $0 == .timeout || $0 == .notRegistered }) {
            records[bundle.url.path] = nil
            save()
            return
        }
        records[bundle.url.path] = Record(modified: Self.modified(bundle), issues: issues)
        save()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        records = [:]
        save()
    }

    /// Bundles the background check still has to look at: never checked, changed since, and not on their way out.
    static func pending(_ bundles: [PluginBundle], saved: [String: [Issue]], forgotten: Set<String>) -> [PluginBundle] {
        bundles.filter { !forgotten.contains($0.id) && saved[$0.id] == nil }
    }

    private func save() {
        try? store.save(records)   // only a cache: the next run checks again
    }

    /// The newest of the bundle folder, its Info.plist and its binary: an installer that rewrites files
    /// inside an existing bundle leaves the folder's own date alone.
    static func modified(_ bundle: PluginBundle) -> Date {
        let files = [bundle.url, bundle.url.appendingPathComponent("Contents/Info.plist")] + [bundle.executable].compactMap { $0 }
        return files.map(date).max() ?? .distantPast
    }

    private static func date(_ url: URL) -> Date {
        // Not URL.resourceValues: a URL caches them, so a plugin updated in place would look unchanged
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
    }
}
