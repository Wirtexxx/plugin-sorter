import Foundation

/// What the draft says about the machine.
struct SupportContext {
    let macOS: String
    let cpu: String
    let appVersion: String
}

/// A message to a plugin developer's support about a plugin that doesn't work. Always in English:
/// the support reads it, not the user. There is no address, so the "To" field stays empty.
struct SupportDraft: Equatable {
    let subject: String
    let body: String

    /// Longest piece of a check's error text that goes into the message.
    static let maxErrorLength = 1500

    /// Built by hand: `URLQueryItem` leaves "+" and "&" in the text, and mail clients disagree on them.
    var mailto: URL {
        let encode = { (text: String) in text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "" }
        return URL(string: "mailto:?subject=" + encode(subject) + "&body=" + encode(body)) ?? URL(string: "mailto:")!
    }

    /// `issues` are the check results by `PluginBundle.id`.
    static func make(plugin: ManagedPlugin, issues: [String: [Issue]], context: SupportContext) -> SupportDraft {
        let home = NSHomeDirectory()
        var lines = ["Hello,", "", "\(plugin.name) \(plugin.version) doesn't work for me.", "", "Formats:"]
        for bundle in plugin.activeBundles {
            let version = bundle.version.isEmpty ? "unknown version" : bundle.version
            let archs = bundle.archs.isEmpty ? "unknown" : bundle.archs.sorted().joined(separator: ", ")
            var line = "- \(bundle.format.rawValue) \(version) (\(archs)): "
            let found = issues[bundle.id] ?? []
            if found.isEmpty {
                line += "works"
            } else {
                line += found.map(describe).joined(separator: "; ")
            }
            lines.append(line)
        }
        lines += ["", "System: macOS \(context.macOS), \(context.cpu)", "Checked with Plugin Sorter \(context.appVersion)"]
        let body = lines.joined(separator: "\n").replacingOccurrences(of: home, with: "~")
        return SupportDraft(subject: "\(plugin.name): problem on macOS \(context.macOS)", body: body)
    }

    private static func describe(_ issue: Issue) -> String {
        switch issue {
        case .noBinary:                  return "the plugin has no executable"
        case .wrongArch(let archs):      return "built for \(archs.joined(separator: ", ")) only"
        case .rosetta:                   return "runs only under Rosetta"
        case .quarantined:               return "blocked by macOS quarantine"
        case .notRegistered:             return "not registered as an Audio Unit"
        case .validationFailed(let why): return "validation failed: " + cut(why)
        case .loadFailed(let why):       return "failed to load: " + cut(why)
        case .timeout:                   return "did not answer in time"
        }
    }

    private static func cut(_ text: String) -> String {
        text.count > maxErrorLength ? String(text.prefix(maxErrorLength)) + "…" : text
    }
}
