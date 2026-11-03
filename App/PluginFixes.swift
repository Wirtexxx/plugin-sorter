import Foundation

/// A one-click repair offered next to a problem found by PluginChecker.
enum Fix: Equatable, Identifiable {
    /// Clear the quarantine flag macOS sets on downloads.
    case unquarantine(URL)
    /// Move a bundle elsewhere in the plugin tree: a nested AU back to Components,
    /// or a bundle another plugin loads from a fixed path back to that path.
    case relocate(from: URL, to: URL)
    /// Make macOS rescan Audio Units.
    case resetAUCache

    var id: String {
        switch self {
        case .unquarantine(let url):        return "unquarantine:\(url.path)"
        case .relocate(let from, let to):   return "relocate:\(from.path)->\(to.path)"
        case .resetAUCache:                 return "reset-au"
        }
    }
}

enum PluginFixes {
    /// Bundle names the sorter must leave in place, one per line (PLUGIN_SORT_KEEP_FILE).
    static let keepFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Plugin Sorter/keep.txt")

    /// Repairs for a bundle's issues, given everything that is installed.
    static func fixes(for bundle: PluginBundle, issues: [Issue], installed: [PluginBundle],
                      root: URL = PluginInventory.root) -> [Fix] {
        var fixes: [Fix] = []
        for issue in issues {
            switch issue {
            case .quarantined:
                fixes.append(.unquarantine(bundle.url))
            case .notRegistered where bundle.nested:
                let destination = root.appendingPathComponent(PluginFormat.au.folder, isDirectory: true)
                    .appendingPathComponent(bundle.url.lastPathComponent)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    fixes.append(.relocate(from: bundle.url, to: destination))
                }
            case .notRegistered:
                fixes.append(.resetAUCache)
            case .validationFailed(let message), .loadFailed(let message):
                // "could not load /Library/Audio/Plug-Ins/VST3/Serum2.vst3": the file it wants was moved
                guard let missing = missingBundle(in: message, root: root),
                      let found = installed.first(where: {
                          $0.url.lastPathComponent == missing.lastPathComponent && $0.url.path != missing.path
                      }) else { continue }
                fixes.append(.relocate(from: found.url, to: missing))
            default:
                break
            }
        }
        var seen = Set<String>()
        return fixes.filter { seen.insert($0.id).inserted }
    }

    /// The first plugin bundle path inside `root` mentioned in an error that doesn't exist on disk.
    static func missingBundle(in message: String, root: URL) -> URL? {
        // Paths can contain spaces, so match lazily up to a bundle extension followed by a boundary.
        // No quotes or line breaks inside, so one path never runs into the next; "/" ends the bundle
        // when the error names a file inside it (…/Serum2.vst3/Contents/MacOS/Serum2).
        let pattern = NSRegularExpression.escapedPattern(for: root.path)
            + "/[^'\"\\n]+?\\.(?:vst3|component|clap|vst)(?=$|[/\\s\"',:;)])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(message.startIndex..., in: message)
        for match in regex.matches(in: message, range: range) {
            guard let swiftRange = Range(match.range, in: message) else { continue }
            let path = String(message[swiftRange])
            if !path.contains("/../") && !FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Whether a relocation puts a bundle back where another plugin expects it, so sorting must keep it there.
    static func isDependency(_ fix: Fix) -> Bool {
        guard case .relocate(_, let to) = fix else { return false }
        return to.pathExtension.lowercased() != PluginFormat.au.fileExtension
    }

    /// Adds a bundle name to the keep list, once.
    static func keep(_ name: String, file: URL = keepFile) {
        let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let names = existing.split(whereSeparator: \.isNewline).map(String.init)
        guard !names.contains(name) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (names + [name]).joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)
    }
}
