import Foundation

/// A bundle's size and how it looked when measured.
struct MeasuredBundle: Equatable {
    let modified: Date
    let size: Int64
}

/// Disk space used by plugins and by the data their developers keep elsewhere.
enum DiskUsage {
    /// Where developers keep presets, samples and libraries next to the plugin itself.
    static let dataRoots: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Library/Application Support", isDirectory: true),
            home.appendingPathComponent("Library/Application Support", isDirectory: true),
            URL(fileURLWithPath: "/Library/Audio/Presets", isDirectory: true),
            home.appendingPathComponent("Library/Audio/Presets", isDirectory: true),
        ]
    }()

    /// Space a file or folder takes on disk, counting everything inside it.
    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// The size of each bundle, walking only those that changed since `known`: every return to the
    /// window rescans, and walking all of them takes the better part of a second.
    static func sizes(of bundles: [PluginBundle], known: [String: MeasuredBundle]) -> [String: MeasuredBundle] {
        var sizes: [String: MeasuredBundle] = [:]
        for bundle in bundles {
            let modified = CheckCache.modified(bundle)
            if let saved = known[bundle.id], saved.modified == modified {
                sizes[bundle.id] = saved
            } else {
                sizes[bundle.id] = MeasuredBundle(modified: modified, size: size(of: bundle.url))
            }
        }
        return sizes
    }

    /// Every folder directly inside the data locations. List once, then match many vendors against it.
    static func dataFolders(in roots: [URL] = dataRoots) -> [URL] {
        roots.flatMap { root in
            ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                           options: [.skipsHiddenFiles])) ?? [])
                .filter(\.hasDirectoryPath)
        }
    }

    /// Folders named after a developer in the data locations: "FabFilter", "Valhalla DSP" for "Valhalla DSP, LLC",
    /// "Xfer" for "Xfer Records". Short or generic names only match exactly.
    static func vendorFolders(for vendor: String, in roots: [URL] = dataRoots) -> [URL] {
        vendorFolders(for: vendor, among: dataFolders(in: roots))
    }

    static func vendorFolders(for vendor: String, among folders: [URL]) -> [URL] {
        let key = normalize(vendor)
        guard key.count >= 3 else { return [] }
        return folders.filter { folder in
            let name = normalize(folder.lastPathComponent)
            guard name.count >= 3, !ignored.contains(name) else { return false }
            return name == key || (min(name.count, key.count) >= 4 && (key.hasPrefix(name) || name.hasPrefix(key)))
        }
    }

    /// System and app folders that must never be shown as a developer's data.
    private static let ignored: Set<String> = ["apple", "pluginsorter", "audio", "plugins", "plugin"]

    static func normalize(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
}
