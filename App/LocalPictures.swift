import Foundation

/// Screenshots of plugins, kept by the app itself. FL can only hold a picture beside a favourite;
/// these exist for every plugin and go into FL when the plugin becomes one.
final class LocalPictures {
    static let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Plugin Sorter/Pictures", isDirectory: true)

    private let directory: URL

    init(directory: URL = LocalPictures.defaultDirectory) {
        self.directory = directory
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

    func save(_ png: Data, for key: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: url(for: key), options: .atomic)
    }

    /// What a capture can take: only an Audio Unit that's turned on can be opened for a screenshot.
    static func targets(_ plugins: [ManagedPlugin], skipping keys: Set<String>) -> [ManagedPlugin] {
        plugins.filter { plugin in
            !keys.contains(plugin.key) && plugin.activeBundles.contains { $0.format == .au }
        }
    }
}
