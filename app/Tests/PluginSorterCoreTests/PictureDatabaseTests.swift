import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Picture database index")
struct PictureDatabaseTests {
    static let json = """
    {
      "version": 1,
      "pictures": {
        "serum2|xfer": { "file": "pictures/serum2%7Cxfer.png", "sha256": "abc", "width": 1920, "height": 1194 },
        "ozone11|izotope": { "file": "pictures/ozone11%7Cizotope.png", "sha256": "def", "width": 2000, "height": 980,
                             "aliases": ["izozone11|izotope"] }
      }
    }
    """

    private func entry(_ file: String) -> PictureIndex.Entry {
        PictureIndex.Entry(file: file, sha256: "x", width: 1, height: 1, aliases: nil)
    }

    private func plugin(key: String, auName: String) -> ManagedPlugin {
        var au = PluginBundle(url: URL(fileURLWithPath: "/p/iZOzone11AUHook.component"), format: .au, vendor: "iZotope",
                              version: "1", executable: nil, archs: [], quarantined: false, au: nil, nested: false)
        au.auName = auName
        au.idVendor = "izotope"
        return ManagedPlugin(key: key, name: "Ozone 11", vendor: "iZotope", bundles: [au])
    }

    @Test func aValidIndexIsRead() throws {
        let index = try #require(PictureIndex.parse(Data(Self.json.utf8)))
        #expect(index.pictures["serum2|xfer"]?.sha256 == "abc")
    }

    @Test func emptyDataIsNoIndex() { #expect(PictureIndex.parse(Data()) == nil) }

    @Test func notJSONIsNoIndex() { #expect(PictureIndex.parse(Data("<html>".utf8)) == nil) }

    @Test func anUnknownVersionIsNoIndex() {
        #expect(PictureIndex.parse(Data(Self.json.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2").utf8)) == nil)
    }

    @Test func anOversizedIndexIsNoIndex() {
        var data = Data(Self.json.utf8)
        data.append(Data(repeating: 0x20, count: PictureDatabase.maxIndexBytes))
        #expect(PictureIndex.parse(data) == nil)
    }

    @Test func anyCandidateKeyFindsTheEntry() throws {
        let index = try #require(PictureIndex.parse(Data(Self.json.utf8)))
        #expect(index.entry(for: ["nope", "serum2|xfer"])?.key == "serum2|xfer")
    }

    @Test func anAliasFindsTheEntry() throws {
        let index = try #require(PictureIndex.parse(Data(Self.json.utf8)))
        #expect(index.entry(for: ["izozone11|izotope"])?.key == "ozone11|izotope")
    }

    @Test func unsafeFilesHaveNoAddress() {
        #expect(PictureDatabase.url(of: entry("/etc/passwd.png")) == nil)
        #expect(PictureDatabase.url(of: entry("pictures/../../x.png")) == nil)
        #expect(PictureDatabase.url(of: entry("pictures/x.jpg")) == nil)
    }

    @Test func aFileIsAddressedUnderTheBaseWithItsPercentSignEscaped() {
        let url = PictureDatabase.url(of: entry("pictures/serum2%7Cxfer.png"))
        #expect(url?.absoluteString == PictureDatabase.base.absoluteString + "pictures/serum2%257Cxfer.png")
    }

    @Test func pictureKeysTryTheKeyThenTheAudioUnitName() {
        let keys = plugin(key: "izozone11auhook|izotope", auName: "Ozone 11").pictureKeys
        #expect(keys == ["izozone11auhook|izotope", "ozone11|izotope"])
    }

    @Test func pictureKeysHaveNoRepeats() {
        #expect(plugin(key: "ozone11|izotope", auName: "Ozone 11").pictureKeys == ["ozone11|izotope"])
    }

    @Test func wavesKeysComeFromTheFavouriteName() {
        #expect(PictureKey.waves("CLA-76 Stereo") == "waves|cla76stereo")
    }
}

@Suite("When to fetch from the database")
struct DatabaseActionTests {
    private func index(sha: String) -> PictureIndex {
        PictureIndex(version: 1, pictures: ["a|v": .init(file: "pictures/a.png", sha256: sha, width: 1, height: 1, aliases: nil)])
    }

    @Test func aPluginWithoutAPictureIsDownloaded() {
        #expect(PictureDatabase.action(candidates: ["a|v"], hasLocal: false, downloadedSHA: nil, index: index(sha: "a"))
                == .download(key: "a|v", entry: index(sha: "a").pictures["a|v"]!))
    }

    @Test func aPluginMissingFromTheDatabaseIsSkipped() {
        #expect(PictureDatabase.action(candidates: ["b|v"], hasLocal: false, downloadedSHA: nil, index: index(sha: "a")) == .skip)
        #expect(PictureDatabase.action(candidates: ["a|v"], hasLocal: false, downloadedSHA: nil, index: nil) == .skip)
    }

    @Test func anOwnScreenshotIsNeverReplaced() {
        #expect(PictureDatabase.action(candidates: ["a|v"], hasLocal: true, downloadedSHA: nil, index: index(sha: "a")) == .skip)
    }

    @Test func anUnchangedDownloadStays() {
        #expect(PictureDatabase.action(candidates: ["a|v"], hasLocal: true, downloadedSHA: "a", index: index(sha: "a")) == .skip)
    }

    @Test func aChangedDownloadIsFetchedAgain() {
        #expect(PictureDatabase.action(candidates: ["a|v"], hasLocal: true, downloadedSHA: "a", index: index(sha: "b"))
                == .download(key: "a|v", entry: index(sha: "b").pictures["a|v"]!))
    }
}
