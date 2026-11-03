import AppKit

/// FL Studio itself: whether it's open while Plugin Sorter changes its plugin database.
enum FLStudio {
    static let bundleID = "com.image-line.flstudio"

    static func isRunning(_ bundleIDs: [String?]) -> Bool { bundleIDs.contains(bundleID) }

    static var isRunning: Bool { isRunning(NSWorkspace.shared.runningApplications.map(\.bundleIdentifier)) }
}
