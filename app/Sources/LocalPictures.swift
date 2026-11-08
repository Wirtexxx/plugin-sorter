import Foundation

/// Screenshots of plugins, kept by the app itself. FL can only hold a picture beside a favourite;
/// these exist for every plugin and go into FL when the plugin becomes one.
final class LocalPictures {
    static let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Plugin Sorter/Pictures", isDirectory: true)

    private let directory: URL
    /// Plugins that wouldn't open, with the version that didn't: they cost up to 25 seconds each, and
    /// crash or hang the same way next time. An update gets another try.
    private let failureStore: JSONStore<[String: String]>
    private var failures: [String: String]
    /// Pictures that came from the shared database, with the sha256 they had there: an author's fix replaces them.
    private let downloadStore: JSONStore<[String: String]>
    private var downloads: [String: String]
    private let lock = NSLock()

    init(directory: URL = LocalPictures.defaultDirectory) {
        self.directory = directory
        failureStore = JSONStore(url: directory.appendingPathComponent("failed.json"))
        failures = failureStore.load() ?? [:]
        downloadStore = JSONStore(url: directory.appendingPathComponent("database.json"))
        downloads = downloadStore.load() ?? [:]
    }

    func downloadedSHA(of key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return downloads[key]
    }

    func saveDownloaded(_ png: Data, for key: String, sha256: String) throws {
        try write(png, for: key)
        setDownload(sha256, for: key)
    }

    private func setDownload(_ sha256: String?, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        guard downloads[key] != sha256 else { return }
        downloads[key] = sha256
        try? downloadStore.save(downloads)   // at worst a picture of ours counts as one from the database
    }

    func noteFailures(_ plugins: [ManagedPlugin]) {
        lock.lock()
        defer { lock.unlock() }
        for plugin in plugins { failures[plugin.key] = plugin.version }
        try? failureStore.save(failures)   // at worst they're tried again
    }

    func forgetFailures() {
        lock.lock()
        defer { lock.unlock() }
        failures = [:]
        try? failureStore.save(failures)
    }

    /// Of these plugins, the ones that failed in the version installed now.
    func failedKeys(among plugins: [ManagedPlugin]) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(plugins.filter { failures[$0.key] == $0.version }.map(\.key))
    }

    /// The screenshot of a plugin that was uninstalled.
    func remove(_ key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
        setDownload(nil, for: key)
    }

    /// Plugin keys hold any character, so the file name is percent-encoded: nothing can leave the folder.
    func url(for key: String) -> URL {
        let name = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        return directory.appendingPathComponent(name).appendingPathExtension("png")
    }

    /// Keys of the plugins with a screenshot. Reads the disk.
    var keys: Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return Set(files.filter { $0.pathExtension == "png" }
            .compactMap { $0.deletingPathExtension().lastPathComponent.removingPercentEncoding })
    }

    /// The app's own screenshot: from now on the database leaves it alone.
    func save(_ png: Data, for key: String) throws {
        try write(png, for: key)
        setDownload(nil, for: key)
    }

    private func write(_ png: Data, for key: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: url(for: key), options: .atomic)
    }

    /// What a capture can take: only an Audio Unit that's turned on can be opened for a screenshot.
    /// A WaveShell isn't one: its plugins are photographed as favourites, each under its own name.
    static func targets(_ plugins: [ManagedPlugin], skipping keys: Set<String>) -> [ManagedPlugin] {
        plugins.filter { plugin in
            !keys.contains(plugin.key) && !plugin.isWaveShell && plugin.activeBundles.contains { $0.format == .au }
        }
    }
}
