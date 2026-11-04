import AppKit

/// Pictures for the card view, read once and kept until the file changes.
/// Reads the disk, so not for the main thread.
final class CardPictures {
    static let shared = CardPictures()

    private final class Entry {
        let modified: Date
        let image: NSImage
        init(modified: Date, image: NSImage) { self.modified = modified; self.image = image }
    }

    private let cache = NSCache<NSString, Entry>()

    /// The picture as last read, without touching the disk: safe while the list scrolls.
    func cached(at url: URL) -> NSImage? { cache.object(forKey: url.path as NSString)?.image }

    func image(at url: URL) -> NSImage? {
        let key = url.path as NSString
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else {
            cache.removeObject(forKey: key)
            return nil
        }
        if let entry = cache.object(forKey: key), entry.modified == modified { return entry.image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(Entry(modified: modified, image: image), forKey: key)
        return image
    }
}
