import AppKit
import CryptoKit
import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Fetching pictures from the database")
struct PictureFetchTests {
    private let dir: TempDir
    init() throws { dir = try TempDir() }

    private static func png() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    private static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// A database holding the given pictures, as `fetch` sees it; counts every request by URL.
    private final class Server {
        var files: [URL: Data] = [:]
        var requests: [URL] = []
        var delay: TimeInterval = 0

        init(_ pictures: [String: Data], index: Data? = nil, sha: (Data) -> String) {
            var entries: [String: PictureIndex.Entry] = [:]
            for (key, data) in pictures {
                let name = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! + ".png"
                let entry = PictureIndex.Entry(file: "pictures/" + name, sha256: sha(data), width: 4, height: 4, aliases: nil)
                entries[key] = entry
                files[PictureDatabase.url(of: entry)!] = data
            }
            files[PictureDatabase.indexURL] = index ?? (try! JSONEncoder().encode(PictureIndex(version: 1, pictures: entries)))
        }

        func fetch(_ url: URL) -> Data? {
            requests.append(url)
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            return files[url]
        }
    }

    private func library(_ server: Server) -> (FLLibrary, LocalPictures) {
        let local = LocalPictures(directory: dir.path("p"))
        return (FLLibrary(demo: true, local: local, shooter: { _ in nil }, fetch: server.fetch), local)
    }

    @Test @MainActor func aPictureInTheDatabaseIsSavedAsFromTheDatabase() async {
        let picture = Self.png()
        let server = Server(["a|v": picture], sha: Self.sha)
        let (library, local) = library(server)
        var next = 0
        library.fetchFromDatabase(["a|v": ["a|v"]]) { next += 1 }
        await wait { next == 1 }
        #expect(local.keys == ["a|v"])
        #expect(local.downloadedSHA(of: "a|v") == Self.sha(picture))
        #expect(library.localKeys == ["a|v"])
        #expect(!library.busy)
    }

    @Test @MainActor func aPluginMissingFromTheDatabaseIsLeftForTheCapture() async {
        let (library, local) = library(Server([:], sha: Self.sha))
        var next = 0
        library.fetchFromDatabase(["a|v": ["a|v"]]) { next += 1 }
        await wait { next == 1 }
        #expect(local.keys.isEmpty)
    }

    @Test @MainActor func noIndexMeansNoErrorAndTheCaptureGoesOn() async {
        let server = Server([:], sha: Self.sha)
        server.files = [:]
        let (library, local) = library(server)
        var next = 0
        library.fetchFromDatabase(["a|v": ["a|v"]]) { next += 1 }
        await wait { next == 1 }
        #expect(local.keys.isEmpty)
        #expect(library.status == .idle)
    }

    @Test @MainActor func aFileThatDoesntMatchItsHashIsNotSaved() async {
        let server = Server(["a|v": Self.png()], sha: { _ in "0000" })
        let (library, local) = library(server)
        var next = 0
        library.fetchFromDatabase(["a|v": ["a|v"]]) { next += 1 }
        await wait { next == 1 }
        #expect(local.keys.isEmpty)
    }

    @Test @MainActor func aFileThatIsNoPictureIsNotSaved() async {
        let junk = Data("<html>".utf8)
        let server = Server(["a|v": junk], sha: Self.sha)
        let (library, local) = library(server)
        var next = 0
        library.fetchFromDatabase(["a|v": ["a|v"]]) { next += 1 }
        await wait { next == 1 }
        #expect(local.keys.isEmpty)
    }

    @Test @MainActor func anOwnScreenshotIsNotFetched() async throws {
        let server = Server(["a|v": Self.png()], sha: Self.sha)
        let (library, local) = library(server)
        try local.save(Data([9]), for: "a|v")
        var next = 0
        library.fetchFromDatabase(["a|v": ["a|v"]]) { next += 1 }
        await wait { next == 1 }
        #expect(server.requests == [PictureDatabase.indexURL])
        #expect(try Data(contentsOf: local.url(for: "a|v")) == Data([9]))
    }

    @Test @MainActor func aPictureIsSavedUnderThePluginsOwnKeyWhenFoundByAnother() async {
        let server = Server(["ozone11|izotope": Self.png()], sha: Self.sha)
        let (library, local) = library(server)
        var next = 0
        library.fetchFromDatabase(["izozone11auhook|izotope": ["izozone11auhook|izotope", "ozone11|izotope"]]) { next += 1 }
        await wait { next == 1 }
        #expect(local.keys == ["izozone11auhook|izotope"])
    }

    @Test @MainActor func aStopEndsTheDownloadsAndWhatComesNext() async {
        var pictures: [String: Data] = [:]
        for n in 0..<20 { pictures["p\(n)|v"] = Self.png() }
        let server = Server(pictures, sha: Self.sha)
        server.delay = 0.05
        let (library, local) = library(server)
        var next = 0
        library.fetchFromDatabase(Dictionary(uniqueKeysWithValues: pictures.keys.map { ($0, [$0]) })) { next += 1 }
        library.stopCapture()
        await wait { !library.busy }
        #expect(local.keys.count < 20)
        #expect(next == 0)
    }
}

@Suite("Pictures from the database that may have changed")
struct DownloadedRefreshTests {
    private let dir: TempDir
    init() throws { dir = try TempDir() }

    private func plugin(_ key: String) -> ManagedPlugin {
        ManagedPlugin(key: key, name: key, vendor: "V", bundles: [])
    }

    @Test func downloadedPicturesAreCheckedAgainButOwnOnesAreNot() throws {
        let local = LocalPictures(directory: dir.path("p"))
        try local.saveDownloaded(Data([1]), for: "a|v", sha256: "s")
        try local.save(Data([2]), for: "b|v")
        try local.saveDownloaded(Data([3]), for: PictureKey.waves("CLA-76 Stereo"), sha256: "s")
        let library = FLLibrary(demo: true, local: local)
        let wanted = library.downloadedPictures(among: [plugin("a|v"), plugin("b|v"), plugin("c|v")])
        #expect(wanted == ["a|v": ["a|v"], "waves|cla76stereo": ["waves|cla76stereo"]])
    }
}
