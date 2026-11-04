import Foundation

enum CleanupKind: Equatable {
    /// A newer version of the same plugin is installed; `newest` is its name.
    case olderVersion(newest: String)
    /// Two copies of one format of the same plugin; this is the older one.
    case extraCopy
    /// An old VST2 file next to the VST3 of the same plugin.
    case legacyVST2
}

/// Files the app suggests removing. Only a suggestion: nothing is checked until the user does it.
struct CleanupFinding: Identifiable, Equatable {
    var id: String { bundles.map(\.path).joined(separator: "|") }
    let kind: CleanupKind
    let pluginKey: String
    let name: String
    let bundles: [URL]
}

enum Cleanup {
    /// The version in a name and the name without it, both for matching: "FabFilter Pro-Q 4" is ("fabfilterproq", 4).
    /// A version is 1–2 digits at the end after a space or a letter, with an optional "V" in front. A number
    /// after a hyphen or of more digits is part of the name (Jupiter-8, SSL 4000), and a name with
    /// no number is version 1.
    static func family(of name: String) -> (base: String, version: Int)? {
        var base = name
        var version = 1
        let range = NSRange(name.startIndex..., in: name)
        if let match = versionPattern.firstMatch(in: name, range: range),
           let head = Range(match.range(at: 1), in: name), let number = Range(match.range(at: 2), in: name) {
            base = String(name[head])
            version = Int(name[number]) ?? 1
        }
        let key = FLFavorites.normalize(base)
        return key.isEmpty ? nil : (key, version)
    }

    private static let versionPattern: NSRegularExpression = {
        // Either a space (and maybe "V") or a letter (and maybe "V") sits in front of the digits
        try! NSRegularExpression(pattern: "^(.+?)(?:[ ]+[Vv]?|(?<=[A-Za-z])[Vv]?)(\\d{1,2})$")
    }()

    /// What can go, given every installed plugin (turned-off ones count as installed).
    static func findings(_ plugins: [ManagedPlugin]) -> [CleanupFinding] {
        var result: [CleanupFinding] = []
        var covered: Set<String> = []

        // Older versions: the same developer's chain of names that differ by a trailing number
        var chains: [String: [(plugin: ManagedPlugin, version: Int)]] = [:]
        for plugin in plugins where !isWaves(plugin) && !plugin.vendor.isEmpty {
            guard let family = family(of: plugin.name) else { continue }
            chains[FLFavorites.normalize(plugin.vendor) + "|" + family.base, default: []].append((plugin, family.version))
        }
        for (key, chain) in chains where chain.count > 1 && !separateProducts.contains(String(key.split(separator: "|").last ?? "")) {
            for run in versionRuns(chain) {
                guard let newest = run.max(by: { $0.version < $1.version }) else { continue }
                for item in run where item.version < newest.version {
                    result.append(CleanupFinding(kind: .olderVersion(newest: newest.plugin.name), pluginKey: item.plugin.key,
                                                 name: item.plugin.name, bundles: item.plugin.bundles.map(\.url)))
                    covered.insert(item.plugin.key)
                }
            }
        }

        // Within one plugin: a second copy of a format, and VST2 beside VST3
        for plugin in plugins where !covered.contains(plugin.key) && !isWaves(plugin) {
            for kind in [CleanupKind.extraCopy, .legacyVST2] {
                let bundles = kind == .extraCopy ? extraCopies(in: plugin) : legacyVST2(in: plugin)
                if !bundles.isEmpty {
                    result.append(CleanupFinding(kind: kind, pluginKey: plugin.key, name: plugin.name, bundles: bundles.map(\.url)))
                }
            }
        }
        return result.sorted { a, b in
            let order = a.name.localizedCaseInsensitiveCompare(b.name)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }

    /// Splits a chain where the numbers jump: versions of one plugin follow each other (Pro-Q 2, 3, 4; Ozone 9, 11),
    /// while models of a series don't (Jupiter 4 and 8, DX7 and DX11, Model 72 and 84). Runs of one are dropped.
    private static func versionRuns(_ chain: [(plugin: ManagedPlugin, version: Int)]) -> [[(plugin: ManagedPlugin, version: Int)]] {
        let sorted = chain.sorted { $0.version != $1.version ? $0.version < $1.version : $0.plugin.key < $1.plugin.key }
        var runs: [[(plugin: ManagedPlugin, version: Int)]] = []
        for item in sorted {
            if let last = runs.last?.last, item.version - last.version <= maxVersionStep {
                runs[runs.count - 1].append(item)
            } else {
                runs.append([item])
            }
        }
        return runs.filter { $0.count > 1 }
    }

    private static let maxVersionStep = 2

    /// Names where the number is another product, not an update: both stay in use side by side.
    private static let separateProducts: Set<String> = ["serum"]

    /// Everything but the newest copy of each format. A turned-off copy is the user's choice, so it is
    /// only compared with other turned-off copies.
    private static func extraCopies(in plugin: ManagedPlugin) -> [PluginBundle] {
        let groups = Dictionary(grouping: plugin.bundles) { "\($0.format.rawValue)|\($0.isDisabled)" }
        return groups.values.filter { $0.count > 1 }.flatMap { copies -> [PluginBundle] in
            let sorted = copies.sorted { a, b in
                let order = a.version.compare(b.version, options: .numeric)
                if order != .orderedSame { return order == .orderedDescending }
                // Equal versions: the one in a developer folder is the sorted, kept one
                if a.nested != b.nested { return a.nested }
                return a.url.path < b.url.path
            }
            return Array(sorted.dropFirst())
        }
    }

    private static func legacyVST2(in plugin: ManagedPlugin) -> [PluginBundle] {
        plugin.bundles.filter { old in
            old.format == .vst && plugin.bundles.contains { $0.format == .vst3 && $0.isDisabled == old.isDisabled }
        }
    }

    /// Waves plugins are managed by Waves Central.
    private static func isWaves(_ plugin: ManagedPlugin) -> Bool {
        plugin.name.hasPrefix("WaveShell") || FLFavorites.normalize(plugin.vendor).hasPrefix("waves")
            || plugin.bundles.contains { $0.bundleID.lowercased().contains("wavesaudio") }
    }
}
