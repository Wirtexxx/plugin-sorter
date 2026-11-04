import Combine
import Foundation

/// The colour of a label. The cases are the theme's colours; the UI picks the actual shade.
enum LabelColor: String, Codable, CaseIterable {
    case accent, mint, amber, danger
}

/// What the user attached to one plugin: any number of tags and one colour.
struct PluginLabels: Codable, Equatable {
    var tags: [String] = []
    var color: LabelColor?

    var isEmpty: Bool { tags.isEmpty && color == nil }
}

/// The user's tags and colours, by `plugin.key` so they outlive sorting and updates. Written to disk
/// on every change.
final class UserLabels: ObservableObject {
    static let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Plugin Sorter/labels.json")

    @Published private(set) var all: [String: PluginLabels] = [:]
    /// The last save that failed, for the window to say so.
    @Published private(set) var saveError: String?
    private let store: JSONStore<[String: PluginLabels]>

    init(url: URL = UserLabels.defaultURL) {
        store = JSONStore(url: url)
        all = store.load() ?? [:]
    }

    /// Every tag in use with the number of plugins that have it: most used first, then by name.
    var allTags: [(tag: String, count: Int)] {
        var counts: [String: (tag: String, count: Int)] = [:]
        for (_, labels) in all.sorted(by: { $0.key < $1.key }) {
            for tag in labels.tags {
                let id = tag.lowercased()
                counts[id] = (counts[id]?.tag ?? tag, (counts[id]?.count ?? 0) + 1)
            }
        }
        return counts.values.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending
        }
    }

    func labels(of key: String) -> PluginLabels { all[key] ?? PluginLabels() }

    /// Spaces around are cut; a tag that differs only in case from one already there is not added.
    func addTag(_ tag: String, to key: String) {
        let tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        change(key) { labels in
            guard !labels.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
            labels.tags.append(tag)
        }
    }

    func removeTag(_ tag: String, from key: String) {
        change(key) { labels in labels.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame } }
    }

    func setColor(_ color: LabelColor?, for key: String) {
        change(key) { $0.color = color }
    }

    private func change(_ key: String, _ edit: (inout PluginLabels) -> Void) {
        var next = all
        var labels = next[key] ?? PluginLabels()
        edit(&labels)
        next[key] = labels.isEmpty ? nil : labels
        guard next != all else { return }
        all = next
        do {
            try store.save(next)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
