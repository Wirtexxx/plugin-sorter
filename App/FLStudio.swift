import AppKit

/// Programs that load plugins: a file moved under them is a crash or a missing plugin in an open project.
enum HostApps {
    /// Bundle identifiers start with these; versions end up in the rest ("com.steinberg.cubase14").
    private static let known: [(prefix: String, name: String)] = [
        ("com.image-line.flstudio", "FL Studio"), ("com.ableton.live", "Ableton Live"), ("com.apple.logic", "Logic Pro"),
        ("com.apple.garageband", "GarageBand"), ("com.apple.mainstage", "MainStage"), ("com.steinberg.cubase", "Cubase"),
        ("com.steinberg.nuendo", "Nuendo"), ("com.cockos.reaper", "REAPER"), ("com.bitwig.", "Bitwig Studio"),
        ("com.presonus.studioone", "Studio One"), ("com.avid.ProTools", "Pro Tools"), ("com.propellerheads.reason", "Reason"),
        ("com.reasonstudios.reason", "Reason"), ("com.motu.DigitalPerformer", "Digital Performer"),
    ]

    /// Names of the hosts among these bundle identifiers, each once.
    static func running(_ bundleIDs: [String?]) -> [String] {
        var names: [String] = []
        for id in bundleIDs.compactMap({ $0?.lowercased() }) {
            if let host = known.first(where: { id.hasPrefix($0.prefix.lowercased()) }), !names.contains(host.name) {
                names.append(host.name)
            }
        }
        return names
    }

    static var running: [String] { running(NSWorkspace.shared.runningApplications.map(\.bundleIdentifier)) }
}

/// FL Studio itself: whether it's open while Plugin Sorter changes its plugin database.
enum FLStudio {
    static let bundleID = "com.image-line.flstudio"

    static func isRunning(_ bundleIDs: [String?]) -> Bool { bundleIDs.contains(bundleID) }

    static var isRunning: Bool { isRunning(NSWorkspace.shared.runningApplications.map(\.bundleIdentifier)) }
}
