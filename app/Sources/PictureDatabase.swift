import Foundation

/// `index.json` of the shared picture database: which picture belongs to which plugin.
struct PictureIndex: Codable, Equatable {
    struct Entry: Codable, Equatable {
        /// Path inside the repository, e.g. "pictures/serum2%7Cxfer.png" (the name is the encoded key).
        let file: String
        let sha256: String
        let width: Int
        let height: Int
        /// Other keys the same plugin gets on other Macs.
        var aliases: [String]?
    }

    static let version = 1

    let version: Int
    var pictures: [String: Entry]

    /// Nil for anything unusable: empty, not JSON, too large or a version this app doesn't know.
    static func parse(_ data: Data) -> PictureIndex? {
        guard !data.isEmpty, data.count <= PictureDatabase.maxIndexBytes,
              let index = try? JSONDecoder().decode(PictureIndex.self, from: data),
              index.version == version else { return nil }
        return index
    }

    /// The first candidate that has a picture, by its own key or an alias.
    func entry(for candidates: [String]) -> (key: String, entry: Entry)? {
        for candidate in candidates {
            if let entry = pictures[candidate] { return (candidate, entry) }
        }
        for candidate in candidates {
            if let found = pictures.first(where: { $0.value.aliases?.contains(candidate) ?? false }) {
                return (found.key, found.value)
            }
        }
        return nil
    }
}

/// The shared pictures: a public GitHub repository, read over plain HTTPS. Nothing is ever written there.
enum PictureDatabase {
    static let base = URL(string: "https://raw.githubusercontent.com/Wirtexxx/plugin-sorter-pictures/main/")!
    static var indexURL: URL { base.appendingPathComponent("index.json") }
    static let maxIndexBytes = 5_000_000

    /// Nil for a path that could point outside the repository's pictures or isn't a PNG.
    static func url(of entry: PictureIndex.Entry) -> URL? {
        let parts = entry.file.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !entry.file.hasPrefix("/"), entry.file.hasSuffix(".png"),
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        // File names hold a literal "%" (the encoded key), which a URL must carry as "%25"
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let path = parts.compactMap { $0.addingPercentEncoding(withAllowedCharacters: allowed) }
        guard path.count == parts.count else { return nil }
        return URL(string: base.absoluteString + path.joined(separator: "/"))
    }
}

extension ManagedPlugin {
    /// Keys to look the plugin up by: its own, then the ones its Audio Units' names give, which other Macs may use.
    var pictureKeys: [String] {
        var keys = [key]
        for bundle in bundles where bundle.format == .au && !bundle.auName.isEmpty {
            let named = PluginInventory.key(for: URL(fileURLWithPath: bundle.auName)) + "|" + bundle.idVendor
            if !keys.contains(named) { keys.append(named) }
        }
        return keys
    }
}

enum PictureKey {
    /// Waves plugins share one WaveShell, so they're keyed by the name FL gives each favourite.
    static func waves(_ title: String) -> String { "waves|" + FLFavorites.normalize(title) }
}

enum DatabaseAction: Equatable {
    /// `key` is the one the index knows the picture by, which may differ from the plugin's own.
    case download(key: String, entry: PictureIndex.Entry)
    case skip
}

extension PictureDatabase {
    /// A plugin's own screenshot is never replaced; a picture from the database is, once the author changes it.
    static func action(candidates: [String], hasLocal: Bool, downloadedSHA: String?, index: PictureIndex?) -> DatabaseAction {
        guard let found = index?.entry(for: candidates) else { return .skip }
        if hasLocal && (downloadedSHA == nil || downloadedSHA == found.entry.sha256) { return .skip }
        return .download(key: found.key, entry: found.entry)
    }
}
