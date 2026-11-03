import Foundation

/// Which plugins the app has already seen, to point out the ones installed since. A plugin counts by its
/// key, so a moved bundle or a new format of a known plugin is not new. The first scan takes everything
/// for known; the "new" mark stays until `markAllSeen`.
final class KnownPlugins {
    private struct Saved: Codable {
        var known: [String]
        var new: [String]
    }

    static let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Plugin Sorter/known-plugins.json")

    private let url: URL
    /// Nil until a scan with plugins in it: that scan is the first run.
    private var known: Set<String>?
    private var new: Set<String> = []

    init(url: URL = KnownPlugins.defaultURL) {
        self.url = url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            known = Set(saved.known)
            new = Set(saved.new)
        }
    }

    /// Takes the installed plugins and returns the keys of the new ones. An empty scan changes nothing:
    /// it's a folder that couldn't be read, not a user who removed everything.
    func update(with plugins: [ManagedPlugin]) -> Set<String> {
        let keys = Set(plugins.map(\.key))
        guard !keys.isEmpty else { return new }
        let before = (known, new)
        if let known = known {
            new = new.union(keys.subtracting(known)).intersection(keys)
        } else {
            new = []
        }
        known = keys
        if before.0 != known || before.1 != new { save() }
        return new
    }

    func markAllSeen() {
        guard !new.isEmpty else { return }
        new = []
        save()
    }

    private func save() {
        let saved = Saved(known: (known ?? []).sorted(), new: new.sorted())
        try? JSONEncoder().encode(saved).write(to: url, options: .atomic)
    }
}
