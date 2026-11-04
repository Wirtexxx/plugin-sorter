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

/// Reads pictures one at a time, newest request first: while a list scrolls, the card that just came into
/// view matters and the ones that went by don't. Main thread only, apart from the reading.
final class PictureLoader {
    static let shared = PictureLoader { CardPictures.shared.image(at: $0) }

    private struct Request {
        let id: Int
        let url: URL
        let done: (NSImage?) -> Void
    }

    private let read: (URL) -> NSImage?
    private let queue = DispatchQueue(label: "plugin-sorter.pictures", qos: .userInitiated)
    private var waiting: [Request] = []
    private var nextID = 0
    private var reading = false

    init(read: @escaping (URL) -> NSImage?) {
        self.read = read
    }

    /// `done` is called on the main thread. Returns what `cancel` takes.
    func load(_ url: URL, done: @escaping (NSImage?) -> Void) -> Int {
        nextID += 1
        waiting.append(Request(id: nextID, url: url, done: done))
        next()
        return nextID
    }

    func cancel(_ id: Int) {
        waiting.removeAll { $0.id == id }
    }

    private func next() {
        guard !reading, let request = waiting.popLast() else { return }
        reading = true
        queue.async {
            let image = self.read(request.url)
            DispatchQueue.main.async {
                self.reading = false
                request.done(image)
                self.next()
            }
        }
    }
}
