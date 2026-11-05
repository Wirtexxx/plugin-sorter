import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Plugins installed since the last look")
struct KnownPluginsTests {
    private func plugin(_ key: String, formats: [PluginFormat] = [.vst3], folder: String = "", disabled: Bool = false) -> ManagedPlugin {
        let bundles = formats.map { format -> PluginBundle in
            let url = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/\(format.folder)/\(folder)\(key).\(format.fileExtension)")
            return PluginBundle(url: url, format: format, vendor: "V", version: "1", executable: nil, archs: [],
                                quarantined: false, au: nil, nested: !folder.isEmpty, isDisabled: disabled)
        }
        return ManagedPlugin(key: key, name: key, vendor: "V", bundles: bundles)
    }

    private func make() throws -> (KnownPlugins, URL, TempDir) {
        let dir = try TempDir()
        let url = dir.path("known.json")
        return (KnownPlugins(url: url), url, dir)
    }

    @Test func firstRunMarksNothingNew() throws {
        let (known, _, _dir) = try make()
        #expect(known.update(with: [plugin("a"), plugin("b")]).isEmpty)
    }

    @Test func addedPluginIsNew() throws {
        let (known, _, _dir) = try make()
        _ = known.update(with: [plugin("a")])
        #expect(known.update(with: [plugin("a"), plugin("b")]) == ["b"])
    }

    @Test func movedBundleIsNotNew() throws {
        let (known, _, _dir) = try make()
        _ = known.update(with: [plugin("a")])
        #expect(known.update(with: [plugin("a", folder: "Vendor/")]).isEmpty)
    }

    @Test func addedFormatIsNotNew() throws {
        let (known, _, _dir) = try make()
        _ = known.update(with: [plugin("a")])
        #expect(known.update(with: [plugin("a", formats: [.vst3, .au])]).isEmpty)
    }

    @Test func enablingIsNotNew() throws {
        let (known, _, _dir) = try make()
        _ = known.update(with: [plugin("a", disabled: true)])
        #expect(known.update(with: [plugin("a", disabled: false)]).isEmpty)
    }

    @Test func stayNewUntilSeen() throws {
        let (known, _, _dir) = try make()
        _ = known.update(with: [plugin("a")])
        _ = known.update(with: [plugin("a"), plugin("b")])
        #expect(known.update(with: [plugin("a"), plugin("b")]) == ["b"])
        known.markAllSeen()
        #expect(known.update(with: [plugin("a"), plugin("b")]).isEmpty)
    }

    @Test func survivesRelaunch() throws {
        let (known, url, _dir) = try make()
        _ = known.update(with: [plugin("a")])
        _ = known.update(with: [plugin("a"), plugin("b")])
        let again = KnownPlugins(url: url)
        // "a" is still known, "b" is still new, "c" is new now
        #expect(again.update(with: [plugin("a"), plugin("b"), plugin("c")]) == ["b", "c"])
    }

    @Test func removedAndReinstalledIsNewAgain() throws {
        let (known, _, _dir) = try make()
        _ = known.update(with: [plugin("a"), plugin("b")])
        #expect(known.update(with: [plugin("b")]).isEmpty)
        #expect(known.update(with: [plugin("b")]).isEmpty)           // missed twice in a row: forgotten
        #expect(known.update(with: [plugin("a"), plugin("b")]) == ["a"])
    }

    @Test func oneTransientMissDoesNotMakeAPluginNew() throws {
        let (known, url, _dir) = try make()
        _ = known.update(with: [plugin("a"), plugin("b")])
        #expect(known.update(with: [plugin("b")]).isEmpty)           // "a" is mid-move, say
        #expect(known.update(with: [plugin("a"), plugin("b")]).isEmpty)
        // The miss counter is cleared by the return: a later single miss is a first miss again
        #expect(known.update(with: [plugin("b")]).isEmpty)
        #expect(known.update(with: [plugin("a"), plugin("b")]).isEmpty)
        // And it counts across a relaunch
        _ = known.update(with: [plugin("b")])
        let again = KnownPlugins(url: url)
        #expect(again.update(with: [plugin("a"), plugin("b")]).isEmpty)
    }

    @Test func emptyScanChangesNothing() throws {
        let (known, _, _dir) = try make()
        _ = known.update(with: [plugin("a")])
        _ = known.update(with: [plugin("a"), plugin("b")])
        #expect(known.update(with: []) == ["b"])
        #expect(known.update(with: [plugin("a"), plugin("b")]) == ["b"])
    }

    @Test func emptyFirstScanDoesNotCountAsFirstRun() throws {
        let (known, _, _dir) = try make()
        #expect(known.update(with: []).isEmpty)
        #expect(known.update(with: [plugin("a")]).isEmpty)
    }

    @Test func corruptFileActsAsFirstRun() throws {
        let (_, url, _dir) = try make()
        try Data("{ not json".utf8).write(to: url)
        let known = KnownPlugins(url: url)
        #expect(known.update(with: [plugin("a")]).isEmpty)
    }
}
