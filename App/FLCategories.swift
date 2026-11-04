import Foundation

/// Favourites Plugin Sorter moved into category folders, kept so they can be put back.
final class CategoryJournal {
    /// Where each moved .fst is now → where it was before Plugin Sorter first moved it.
    var moves: [String: String] { lock.lock(); defer { lock.unlock() }; return saved }
    /// Read by the window while the favourites' queue changes it.
    private let lock = NSLock()
    private var saved: [String: String] = [:]
    private let url: URL

    static let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Plugin Sorter/fl-categories.json")

    init(url: URL = CategoryJournal.defaultURL) {
        self.url = url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: url),
           let moves = try? JSONDecoder().decode([String: String].self, from: data) {
            saved = moves
        }
    }

    func record(from: URL, to: URL) {
        lock.lock()
        defer { lock.unlock() }
        // A second move keeps where the favourite was in the first place
        let original = saved.removeValue(forKey: from.path) ?? from.path
        if original != to.path { saved[to.path] = original }
        save()
    }

    fileprivate func forget(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        saved[path] = nil
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(saved).write(to: url, options: .atomic)
    }
}

/// FL's category folders in Effects/ and Generators/: the tabs at the bottom of its plugin picker.
enum FLCategories {
    static let effects = ["Delay reverb", "Distortion", "Dynamics", "Effect", "Filter", "Flanger", "Gain", "Misc", "Visual"]
    static let generators = ["Drum", "Misc", "Sampler", "Synth classic", "Synth special"]

    static func folders(_ section: String) -> [String] { section == "Generators" ? generators : effects }

    /// The category folder a favourite is in; nil at the top of its section.
    static func folder(of favorite: Favorite, root: URL = FLDatabase.root) -> String? {
        let section = root.appendingPathComponent(favorite.section, isDirectory: true).standardizedFileURL.pathComponents
        let parent = favorite.fst.deletingLastPathComponent().standardizedFileURL.pathComponents
        guard parent.count > section.count, Array(parent.prefix(section.count)) == section else { return nil }
        return parent[section.count...].joined(separator: "/")
    }

    // MARK: - Choosing a category

    /// VST3 sub-categories and CLAP features that name one FL category.
    private static let effectTags: [(String, [String])] = [
        ("Delay reverb", ["delay", "reverb"]),
        ("Distortion", ["distortion"]),
        ("Dynamics", ["dynamics", "compressor", "limiter", "expander", "gate", "transient", "mastering"]),
        ("Filter", ["eq", "equalizer", "filter"]),
        ("Flanger", ["modulation", "chorus", "flanger", "phaser", "tremolo"]),
        ("Visual", ["analyzer"]),
        ("Misc", ["pitch shift", "pitch-shifter", "pitch correction", "restoration"]),
    ]
    /// Tags too broad to trust over the plugin's name ("Spatial" covers both Haas and reverbs).
    private static let weakEffectTags = ["tools", "spatial", "utility", "mixing", "stereo", "surround"]
    /// Most instruments just say "Synth", samplers included, so a synth is what's left after the name had its say.
    private static let generatorTags: [(String, [String])] = [
        ("Sampler", ["sampler"]),
        ("Drum", ["drum", "drum-machine"]),
    ]

    /// Words in plugin names, checked in order. Short ones must be whole words ("eq" is not in "frequency").
    private static let effectWords: [(String, [String])] = [
        ("Misc", ["trance gate", "tape stop", "reverser", "halftime", "half time", "stutter", "glitch",
                  "pitch", "autotune", "auto-tune", "vocoder", "shifter"]),
        ("Delay reverb", ["verb", "delay", "echo", "plate", "room", "shimmer", "supermassive", "crystalline"]),
        ("Dynamics", ["comp", "limit", "gate", "transient", "maxim", "dynamic", "de-ess", "deess",
                      "god particle", "ott", "soothe", "76", "1176", "la-2a", "la-3a"]),
        ("Filter", ["eq", "filter", "equaliz", "resonat"]),
        ("Flanger", ["chorus", "flang", "phaser", "ensemble", "tremolo", "vibrato", "rotary", "modulat"]),
        ("Distortion", ["dist", "crush", "satur", "drive", "tape", "thermal", "clip", "lofi", "lo-fi",
                        "retro color", "decimat", "fuzz"]),
        ("Visual", ["meter", "analy", "scope", "tuner", "spectrum"]),
        // Not "stereo" or "mono": they end many plugin names (CLA-76 Stereo) without saying what it does
        ("Gain", ["gain", "haas", "pan", "width", "imager", "mixer", "utility"]),
    ]
    private static let generatorWords: [(String, [String])] = [
        ("Drum", ["drum", "kick", "808", "beat", "perc"]),
        ("Sampler", ["sampl", "kontakt", "granul"]),
    ]

    /// The FL category for a plugin: its own tags first, then its name, then FL's catch-all.
    static func guess(section: String, name: String, tags: [String]) -> String {
        let tags = tags.map { $0.lowercased() }
        if section == "Generators" {
            return match(tags, generatorTags)
                ?? words(name, generatorWords)
                ?? "Synth classic"
        }
        return match(tags, effectTags)
            ?? words(name, effectWords)
            ?? (tags.contains(where: weakEffectTags.contains) ? "Gain" : nil)
            ?? "Effect"
    }

    /// The category of the first tag that names one, in the order the plugin lists them.
    private static func match(_ tags: [String], _ table: [(String, [String])]) -> String? {
        for tag in tags {
            if let hit = table.first(where: { $0.1.contains(tag) }) { return hit.0 }
        }
        return nil
    }

    private static func words(_ name: String, _ table: [(String, [String])]) -> String? {
        let text = name.lowercased()
        let tokens = Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        for (folder, keys) in table {
            for key in keys where key.count <= 3 ? tokens.contains(key) : text.contains(key) {
                return folder
            }
        }
        return nil
    }

    // MARK: - Moving

    /// Moves a favourite with its .nfo and picture into `folder` (nil: back to the top of its section).
    /// A name already taken there gets a number, the way Finder does it.
    @discardableResult
    static func move(_ favorite: Favorite, to folder: String?, root: URL = FLDatabase.root,
                     journal: CategoryJournal, pictures: PictureManifest) throws -> URL {
        var dir = root.appendingPathComponent(favorite.section, isDirectory: true)
        if let folder = folder { dir.appendPathComponent(folder, isDirectory: true) }
        guard dir.standardizedFileURL != favorite.fst.deletingLastPathComponent().standardizedFileURL else {
            return favorite.fst
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = freeName(for: favorite.fst, in: dir)
        try relocate(favorite.fst, to: destination, pictures: pictures)
        journal.record(from: favorite.fst, to: destination)
        return destination
    }

    /// Puts every favourite Plugin Sorter moved back where it was, unless something new took its place.
    @discardableResult
    static func restoreAll(journal: CategoryJournal, pictures: PictureManifest) -> Int {
        let fm = FileManager.default
        var restored = 0
        for (current, original) in journal.moves {
            let from = URL(fileURLWithPath: current)
            let to = URL(fileURLWithPath: original)
            guard fm.fileExists(atPath: from.path) else { journal.forget(current); continue }
            guard !fm.fileExists(atPath: to.path) else { continue }
            try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? relocate(from, to: to, pictures: pictures)) != nil {
                journal.forget(current)
                restored += 1
            }
        }
        return restored
    }

    /// Moves Name.fst, Name.nfo and Name.png together, keeping the .nfo pointing at the picture.
    private static func relocate(_ fst: URL, to destination: URL, pictures: PictureManifest) throws {
        let fm = FileManager.default
        let nfo = fst.deletingPathExtension().appendingPathExtension("nfo")
        let png = fst.deletingPathExtension().appendingPathExtension("png")
        let newNfo = destination.deletingPathExtension().appendingPathExtension("nfo")
        let newPng = destination.deletingPathExtension().appendingPathExtension("png")

        try fm.moveItem(at: fst, to: destination)
        if fm.fileExists(atPath: png.path) {
            try fm.moveItem(at: png, to: newPng)
            pictures.move(png, to: newPng)
        }
        if fm.fileExists(atPath: nfo.path) {
            try fm.moveItem(at: nfo, to: newNfo)
            // A renamed favourite needs its Bitmap= line to follow the picture's new name
            if newPng.lastPathComponent != png.lastPathComponent, fm.fileExists(atPath: newPng.path) {
                let data = try? Data(contentsOf: newNfo)
                try FLDatabase.nfoPointing(at: newPng.lastPathComponent, from: data).write(to: newNfo, options: .atomic)
            }
        }
    }

    private static func freeName(for fst: URL, in dir: URL) -> URL {
        let base = fst.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent(fst.lastPathComponent)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n).fst")
            n += 1
        }
        return candidate
    }
}
