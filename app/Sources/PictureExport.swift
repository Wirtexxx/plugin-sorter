import AppKit

/// The author's side of the picture database: lays full-size screenshots out the way the repository
/// keeps them. Only writes into the chosen folder; committing and pushing is left to the author.
enum PictureExport {
    /// - Parameter shots: every key the plugin is known by (the first names the file), and its PNG.
    /// - Returns: how many pictures are new or changed. Entries already in the index stay.
    static func export(_ shots: [(keys: [String], png: Data)], into folder: URL) throws -> Int {
        let indexURL = folder.appendingPathComponent("index.json")
        var index = (try? Data(contentsOf: indexURL)).flatMap(PictureIndex.parse)
            ?? PictureIndex(version: PictureIndex.version, pictures: [:])
        let pictures = folder.appendingPathComponent("pictures", isDirectory: true)
        try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)

        var changed = 0
        for shot in shots {
            guard let key = shot.keys.first, let rep = NSBitmapImageRep(data: shot.png) else { continue }
            let name = LocalPictures.fileName(for: key)
            let aliases = Array(shot.keys.dropFirst())
            let entry = PictureIndex.Entry(file: "pictures/" + name, sha256: FLLibrary.sha256(shot.png),
                                           width: rep.pixelsWide, height: rep.pixelsHigh,
                                           aliases: aliases.isEmpty ? nil : aliases)
            guard index.pictures[key] != entry else { continue }
            try shot.png.write(to: pictures.appendingPathComponent(name), options: .atomic)
            index.pictures[key] = entry
            changed += 1
        }

        // Sorted and indented, so the author's commits show readable diffs
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(index).write(to: indexURL, options: .atomic)
        return changed
    }
}
