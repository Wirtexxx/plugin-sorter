import Foundation

/// A plugin FL Studio found while scanning, from Plugin database/Installed.
struct InstalledEntry: Identifiable {
    var id: String { fst.path }
    let fst: URL
    /// "Effects" or "Generators".
    let section: String
    /// Folder FL files it under: "VST3", "VST", "AudioUnit", "CLAP", "Fruity", …
    let format: String
    let name: String
    let vendor: String
    /// Plugin files FL loads, as written in the .nfo (ps_file_filename_N).
    let files: [String]

    /// Built in and always there: FL's own plugins (inside the app, %FLPath%) and Apple's Audio Units.
    var isNative: Bool {
        format == "Fruity" || files.contains { $0.hasPrefix("%FLPath%") } || (format == "AudioUnit" && vendor == "Apple")
    }

    var shortFormat: String { format == "AudioUnit" ? "AU" : format }
}

/// An entry in FL's browser and plugin picker: an .fst in Plugin database/Effects or Generators.
struct Favorite: Identifiable {
    var id: String { fst.path }
    let fst: URL
    let title: String
    let section: String
    /// The scanned plugin it points to, when it can be matched.
    let entry: InstalledEntry?

    var nfo: URL { fst.deletingPathExtension().appendingPathExtension("nfo") }
    var picture: URL { fst.deletingPathExtension().appendingPathExtension("png") }
    var isStock: Bool { entry?.isNative ?? false }
}

enum Availability: Equatable {
    case available
    /// The plugin's file exists elsewhere in the plugin folders: FL just needs to rescan.
    case moved
    /// The plugin is gone; its favourite only clutters FL's browser.
    case removed
    case unknown
}

/// Favourites that were taken out of FL's browser, kept so they can be put back.
final class FavoriteBackup {
    struct Record: Codable {
        let original: String
        let backup: String
        let date: Date
    }

    static let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Plugin Sorter/Removed favorites", isDirectory: true)

    let directory: URL
    private(set) var records: [Record] = []
    private var journal: URL { directory.appendingPathComponent("removed.json") }

    init(directory: URL = FavoriteBackup.defaultDirectory) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: journal),
           let saved = try? JSONDecoder().decode([Record].self, from: data) {
            records = saved
        }
    }

    fileprivate func add(_ record: Record) {
        records.append(record)
        save()
    }

    fileprivate func remove(where shouldRemove: (Record) -> Bool) {
        records.removeAll(where: shouldRemove)
        save()
    }

    private func save() {
        try? JSONEncoder().encode(records).write(to: journal, options: .atomic)
    }
}

enum FLFavorites {
    static let sections = ["Effects", "Generators"]

    // MARK: - Reading

    /// key=value lines of an .nfo; tolerates a BOM and CRLF.
    static func nfoValues(_ url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        var text = String(decoding: data, as: UTF8.self)
        if text.unicodeScalars.first == "\u{FEFF}" { text = String(text.unicodeScalars.dropFirst()) }
        var values: [String: String] = [:]
        for line in text.components(separatedBy: CharacterSet.newlines) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            values[String(line[..<eq]).lowercased()] = String(line[line.index(after: eq)...])
        }
        return values
    }

    /// Everything FL has scanned, from Installed/<section>/<format>/*.fst.
    static func installed(root: URL = FLDatabase.root) -> [InstalledEntry] {
        var entries: [InstalledEntry] = []
        let fm = FileManager.default
        for section in sections {
            let sectionDir = root.appendingPathComponent("Installed/\(section)", isDirectory: true)
            let formats = (try? fm.contentsOfDirectory(at: sectionDir, includingPropertiesForKeys: nil)) ?? []
            // "New" lists plugins FL just found again under their real format folders
            for formatDir in formats where formatDir.hasDirectoryPath && formatDir.lastPathComponent != "New" {
                let files = (try? fm.contentsOfDirectory(at: formatDir, includingPropertiesForKeys: nil)) ?? []
                for fst in files where fst.pathExtension.lowercased() == "fst" {
                    let nfo = nfoValues(fst.deletingPathExtension().appendingPathExtension("nfo"))
                    let paths = nfo.filter { $0.key.hasPrefix("ps_file_filename_") }
                        .sorted { $0.key < $1.key }
                        .map(\.value)
                    let info = FST.read(fst)
                    entries.append(InstalledEntry(
                        fst: fst, section: section, format: formatDir.lastPathComponent,
                        name: nfo["ps_name"] ?? info?.name ?? fst.deletingPathExtension().lastPathComponent,
                        vendor: nfo["ps_file_vendorname_0"] ?? info?.vendor ?? "",
                        files: paths))
                }
            }
        }
        return entries
    }

    /// Favourites in Effects/ and Generators/ (category folders included), matched to what FL scanned.
    static func favorites(root: URL = FLDatabase.root, installed: [InstalledEntry]) -> [Favorite] {
        // FL writes a favourite as an exact copy of the scanned .fst, so match by content first
        var byContent: [Data: InstalledEntry] = [:]
        var byName: [String: InstalledEntry] = [:]
        // FL's stock favourites differ from the scan and carry no vendor, so they match by name alone
        var byNameOnly: [String: InstalledEntry] = [:]
        for entry in installed {
            if let data = try? Data(contentsOf: entry.fst) { byContent[data] = byContent[data] ?? entry }
            byName[key(entry.section, entry.name, entry.vendor)] = byName[key(entry.section, entry.name, entry.vendor)] ?? entry
            let nameKey = entry.section + "|" + normalize(entry.name)
            byNameOnly[nameKey] = byNameOnly[nameKey] ?? entry
        }

        var favorites: [Favorite] = []
        for section in sections {
            let dir = root.appendingPathComponent(section, isDirectory: true)
            guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
            for case let fst as URL in walker where fst.pathExtension.lowercased() == "fst" {
                let title = fst.deletingPathExtension().lastPathComponent
                var entry = (try? Data(contentsOf: fst)).flatMap { byContent[$0] }
                let info = FST.read(fst)
                if entry == nil, let info = info {
                    entry = byName[key(section, info.name, info.vendor)]
                }
                if entry == nil {
                    entry = [info?.name, title].compactMap { $0 }.lazy
                        .compactMap { byNameOnly[section + "|" + normalize($0)] }.first
                }
                favorites.append(Favorite(fst: fst, title: title,
                                          section: section, entry: entry))
            }
        }
        return favorites
    }

    /// Whether a scanned plugin is still installed.
    /// - Parameters:
    ///   - bundleNames: file names of every plugin bundle found in the plugin folders.
    ///   - audioUnits: registered Audio Units as `auKey(vendor:name:)`; empty when unknown.
    static func availability(_ entry: InstalledEntry, bundleNames: Set<String>, audioUnits: Set<String>) -> Availability {
        if entry.isNative { return .available }
        let paths = entry.files.filter { $0.hasPrefix("/") }
        if !paths.isEmpty {
            if paths.contains(where: { FileManager.default.fileExists(atPath: $0) }) { return .available }
            let names = paths.map { URL(fileURLWithPath: $0).lastPathComponent }
            return names.contains(where: bundleNames.contains) ? .moved : .removed
        }
        if entry.format == "AudioUnit" && !audioUnits.isEmpty {
            return audioUnits.contains(auKey(vendor: entry.vendor, name: entry.name)) ? .available : .removed
        }
        return .unknown
    }

    static func auKey(vendor: String, name: String) -> String { normalize(vendor) + "|" + normalize(name) }

    /// The turned-off Audio Units as `auKey`s. macOS no longer lists them, but they are not gone.
    static func disabledAudioUnitKeys(_ plugins: [ManagedPlugin]) -> Set<String> {
        var keys: Set<String> = []
        for bundle in plugins.flatMap(\.bundles) where bundle.format == .au && bundle.isDisabled {
            let file = bundle.url.deletingPathExtension().lastPathComponent
            keys.insert(auKey(vendor: bundle.vendor, name: file))
            if !bundle.auName.isEmpty { keys.insert(auKey(vendor: bundle.vendor, name: bundle.auName)) }
        }
        return keys
    }

    // MARK: - Changing

    /// Puts a scanned plugin into FL's browser. A second format of the same plugin gets its format in the name.
    @discardableResult
    static func add(_ entry: InstalledEntry, root: URL = FLDatabase.root) throws -> URL {
        let dir = root.appendingPathComponent(entry.section, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = entry.fst.deletingPathExtension().lastPathComponent
        var destination = dir.appendingPathComponent("\(base).fst")
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = dir.appendingPathComponent("\(base) (\(entry.shortFormat)).fst")
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else { return destination }
        try FileManager.default.copyItem(at: entry.fst, to: destination)
        return destination
    }

    /// Takes a favourite out of FL's browser, moving its .fst, .nfo and picture to the backup.
    static func remove(_ favorite: Favorite, backup: FavoriteBackup) throws {
        let folder = backup.directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in [favorite.fst, favorite.nfo, favorite.picture] where FileManager.default.fileExists(atPath: file.path) {
            let target = folder.appendingPathComponent(file.lastPathComponent)
            try FileManager.default.moveItem(at: file, to: target)
            backup.add(FavoriteBackup.Record(original: file.path, backup: target.path, date: Date()))
        }
    }

    /// Puts every removed favourite back where it was, unless something new took its place. Returns how many came back.
    @discardableResult
    static func restoreAll(backup: FavoriteBackup) -> Int {
        var restored = 0
        let fm = FileManager.default
        for record in backup.records {
            let original = URL(fileURLWithPath: record.original)
            guard fm.fileExists(atPath: record.backup), !fm.fileExists(atPath: original.path) else { continue }
            try? fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.moveItem(at: URL(fileURLWithPath: record.backup), to: original)) != nil,
               original.pathExtension.lowercased() == "fst" {
                restored += 1
            }
        }
        backup.remove { !fm.fileExists(atPath: $0.backup) }
        return restored
    }

    // MARK: - Helpers

    private static func key(_ section: String, _ name: String, _ vendor: String) -> String {
        section + "|" + normalize(vendor) + "|" + normalize(name)
    }

    static func normalize(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
}
