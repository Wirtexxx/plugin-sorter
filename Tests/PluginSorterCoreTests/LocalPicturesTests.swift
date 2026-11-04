import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Screenshots kept by the app")
struct LocalPicturesTests {
    private let dir: TempDir
    private var folder: URL { dir.path("Pictures") }

    init() throws { dir = try TempDir() }

    private func plugin(_ key: String, formats: [PluginFormat] = [.au], disabled: Bool = false) -> ManagedPlugin {
        let bundles = formats.map { format in
            PluginBundle(url: URL(fileURLWithPath: "/p/\(key).\(format.fileExtension)"), format: format, vendor: "V",
                         version: "1", executable: nil, archs: [], quarantined: false, au: nil, nested: false,
                         isDisabled: disabled)
        }
        return ManagedPlugin(key: key, name: key, vendor: "V", bundles: bundles)
    }

    @Test func aSavedPictureIsThereAfterARestart() throws {
        try LocalPictures(directory: folder).save(Data([1, 2, 3]), for: "pro-q|fabfilter")
        let again = LocalPictures(directory: folder)
        #expect(again.keys == ["pro-q|fabfilter"])
        #expect(try Data(contentsOf: again.url(for: "pro-q|fabfilter")) == Data([1, 2, 3]))
    }

    @Test func aKeyCannotLeaveTheFolder() {
        let pictures = LocalPictures(directory: folder)
        #expect(pictures.url(for: "../../evil/x").deletingLastPathComponent().standardizedFileURL.path
                == folder.standardizedFileURL.path)
    }

    @Test func differentKeysGetDifferentFiles() {
        let pictures = LocalPictures(directory: folder)
        #expect(pictures.url(for: "a/b") != pictures.url(for: "a|b"))
    }

    @Test func onlyPluginsWithAnAudioUnitCanBeCaptured() {
        let targets = LocalPictures.targets([plugin("au"), plugin("vst", formats: [.vst3])], skipping: [])
        #expect(targets.map(\.key) == ["au"])
    }

    @Test func aTurnedOffAudioUnitIsLeftOut() {
        #expect(LocalPictures.targets([plugin("off", disabled: true)], skipping: []).isEmpty)
    }

    @Test func pluginsWithAPictureAreLeftOut() {
        #expect(LocalPictures.targets([plugin("a"), plugin("b")], skipping: ["a"]).map(\.key) == ["b"])
    }
}
