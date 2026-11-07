import Foundation

/// Categories a plugin reports about itself: VST3 sub-categories ("Fx", "Reverb") or CLAP features
/// ("audio-effect", "reverb"). Read in a separate copy of the app (`--tags`), like the load check,
/// because it means loading the plugin.
enum PluginTags {
    /// Lowercased tags, nil when the plugin couldn't be read.
    static func read(_ format: PluginFormat, _ url: URL) -> [String]? {
        guard format == .vst3 || format == .clap, let helper = Helper.process(["--tags", format.rawValue, url.path]),
              let output = PluginChecker.runLogged(helper, timeout: 30, successMarker: "TAGS OK"),
              output.contains("TAGS OK") else { return nil }
        return output.split(separator: "\n")
            .filter { $0.hasPrefix("TAG ") }
            .map { String($0.dropFirst(4)).lowercased() }
    }
}

/// Tags already read, so sorting again doesn't load every plugin a second time.
/// Plugins that couldn't be read are remembered too: a crashing plugin would otherwise cost a timeout each time.
final class TagCache {
    private struct Record: Codable {
        let modified: Date
        let tags: [String]
    }

    static let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Plugin Sorter/plugin-tags.json")

    private var records: [String: Record] = [:]
    private let store: JSONStore<[String: Record]>
    private let lock = NSLock()

    init(url: URL = TagCache.defaultURL) {
        store = JSONStore(url: url)
        records = store.load() ?? [:]
    }

    /// Safe to call from several threads at once; an updated plugin is read again.
    func tags(_ format: PluginFormat, _ bundle: URL) -> [String] {
        let modified = (try? bundle.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? .distantPast
        lock.lock()
        let cached = records[bundle.path]
        lock.unlock()
        if let cached = cached, cached.modified == modified { return cached.tags }

        let tags = PluginTags.read(format, bundle) ?? []
        lock.lock()
        records[bundle.path] = Record(modified: modified, tags: tags)
        try? store.save(records)   // only a cache: the plugin is read again next time
        lock.unlock()
        return tags
    }
}
