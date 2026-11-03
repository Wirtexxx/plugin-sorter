import Foundation

/// An installer's record of the files it put on disk, as `pkgutil` keeps it. Only the plugin bundles are kept.
struct Receipt: Equatable {
    let id: String
    /// Paths of plugin bundles relative to the disk root, e.g. "Library/Audio/Plug-Ins/VST3/OTT.vst3".
    let files: [String]
}

/// Something a plugin leaves behind when its files are deleted.
struct Leftover: Identifiable, Equatable {
    enum Kind { case preferences, cache, presets, vendorData }
    var id: String { url.path }
    let url: URL
    let kind: Kind
    /// Ticked at first. Never the developer's folder: it may hold libraries the user paid for.
    let preselected: Bool
}

enum Uninstall {
    private static let bundleExtensions: Set<String> = Set(PluginFormat.allCases.map(\.fileExtension))

    /// The plugin bundles in a receipt's file list, cut at the bundle itself, once each.
    static func bundleRoots(in files: [String]) -> [String] {
        var roots: [String] = []
        var seen: Set<String> = []
        for file in files {
            let parts = file.split(separator: "/", omittingEmptySubsequences: true)
            guard let end = parts.firstIndex(where: { bundleExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) else { continue }
            let root = parts[...end].joined(separator: "/")
            if seen.insert(root).inserted { roots.append(root) }
        }
        return roots
    }

    /// File names of the plugin bundles a receipt installed, in lower case.
    private static func bundleNames(of receipt: Receipt) -> Set<String> {
        Set(bundleRoots(in: receipt.files).compactMap { $0.split(separator: "/").last.map { $0.lowercased() } })
    }

    private static func bundleNames(of plugin: ManagedPlugin) -> Set<String> {
        Set(plugin.bundles.map { $0.url.lastPathComponent.lowercased() })
    }

    /// The receipts that installed this plugin, found by file name: sorting moves a plugin out of the place
    /// the installer wrote it to, so the path in the receipt no longer exists.
    static func receipts(in all: [Receipt], for plugin: ManagedPlugin) -> [Receipt] {
        let names = bundleNames(of: plugin)
        return all.filter { !bundleNames(of: $0).isDisjoint(with: names) }
    }

    /// Of a plugin's receipts, those that no other installed plugin belongs to: forgetting a shared one
    /// would make macOS lose track of the plugins that stay.
    static func forgettable(_ receipts: [Receipt], removing: ManagedPlugin, others: [ManagedPlugin]) -> [Receipt] {
        let kept = others.reduce(into: Set<String>()) { $0.formUnion(bundleNames(of: $1)) }
        return receipts.filter { bundleNames(of: $0).isDisjoint(with: kept) }
    }

    /// Letters, digits, dots, hyphens and underscores, starting with a letter or digit, no "..": a name that
    /// can't lead out of the folder it is put in.
    static func isPlainBundleID(_ id: String) -> Bool {
        guard !id.contains(".."), let first = id.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(first), first.isASCII else { return false }
        return id.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)) }
    }

    /// Preferences, caches, presets and the developer's folder that belong to the plugin.
    /// - Parameters:
    ///   - others: every other installed plugin; the developer's folder is only offered when none is from them.
    ///   - dataFolders: the folders found directly inside the data locations (`DiskUsage.dataFolders`).
    static func leftovers(for plugin: ManagedPlugin, others: [ManagedPlugin], home: URL, dataFolders: [URL],
                          fileExists: (URL) -> Bool) -> [Leftover] {
        var found: [Leftover] = []
        let library = home.appendingPathComponent("Library", isDirectory: true)
        // An id comes from the plugin's own Info.plist and goes into a path: only a plain one is used, and
        // never one that another installed plugin has too (its settings would go with this one)
        let sharedIDs = Set(others.flatMap { $0.bundles.map(\.bundleID) })
        var ids: [String] = []
        for id in plugin.bundles.map(\.bundleID) where isPlainBundleID(id) && !sharedIDs.contains(id) && !ids.contains(id) {
            ids.append(id)
        }
        for id in ids {
            let preferences = library.appendingPathComponent("Preferences/\(id).plist")
            if fileExists(preferences) { found.append(Leftover(url: preferences, kind: .preferences, preselected: true)) }
        }
        for id in ids {
            let cache = library.appendingPathComponent("Caches/\(id)", isDirectory: true)
            if fileExists(cache) { found.append(Leftover(url: cache, kind: .cache, preselected: true)) }
        }

        // The user may have put presets of their own there, so a plugin's folder is offered, not ticked
        var names = [plugin.name]
        let prefix = plugin.vendor + " "
        if !plugin.vendor.isEmpty, plugin.name.lowercased().hasPrefix(prefix.lowercased()) {
            names.append(String(plugin.name.dropFirst(prefix.count)))
        }
        for folder in DiskUsage.vendorFolders(for: plugin.vendor, among: dataFolders) {
            let shared = others.contains { !DiskUsage.vendorFolders(for: $0.vendor, among: [folder]).isEmpty }
            if shared {
                for name in names {
                    let own = folder.appendingPathComponent(name, isDirectory: true)
                    if fileExists(own) { found.append(Leftover(url: own, kind: .presets, preselected: false)) }
                }
            } else {
                // The whole folder covers everything inside it
                found.append(Leftover(url: folder, kind: .vendorData, preselected: false))
            }
        }
        return found
    }

    // MARK: - Reading the installer receipts

    private static let cacheLock = NSLock()
    private static var cached: [Receipt]?

    /// Every receipt that installed a plugin bundle. Runs `pkgutil` once per package, about a dozen
    /// seconds for a big library, so never on the main thread; the result is kept until the app quits.
    static func loadReceipts() -> [Receipt] {
        cacheLock.lock()
        if let cached = cached {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let ids = output(of: ["--pkgs"]).split(separator: "\n").map(String.init).filter { !$0.hasPrefix("com.apple.") }
        var loaded = [Receipt?](repeating: nil, count: ids.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: ids.count) { index in
            let files = bundleRoots(in: output(of: ["--files", ids[index]]).split(separator: "\n").map(String.init))
            guard !files.isEmpty else { return }
            lock.lock()
            loaded[index] = Receipt(id: ids[index], files: files)
            lock.unlock()
        }
        let receipts = loaded.compactMap { $0 }
        cacheLock.lock()
        cached = receipts
        cacheLock.unlock()
        return receipts
    }

    /// Drops receipts that were forgotten, so the next window doesn't offer them again.
    static func dropFromCache(_ ids: Set<String>) {
        cacheLock.lock()
        cached = cached?.filter { !ids.contains($0.id) }
        cacheLock.unlock()
    }

    private static func output(of arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
