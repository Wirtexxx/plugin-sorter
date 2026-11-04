import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Your own tags and colour labels")
struct UserLabelsTests {
    private func make() throws -> (UserLabels, URL, TempDir) {
        let dir = try TempDir()
        let url = dir.path("labels.json")
        return (UserLabels(url: url), url, dir)
    }

    @Test func tagsAreTrimmedAndCaseInsensitivelyUnique() throws {
        let (labels, _, _dir) = try make()
        labels.addTag(" Drums ", to: "ott")
        labels.addTag("drums", to: "ott")
        labels.addTag("DRUMS", to: "ott")
        #expect(labels.labels(of: "ott").tags == ["Drums"])
    }

    @Test func emptyTagIsIgnored() throws {
        let (labels, url, _dir) = try make()
        labels.addTag("   ", to: "ott")
        labels.addTag("", to: "ott")
        #expect(labels.all.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func labelsSurviveRelaunch() throws {
        let (labels, url, _dir) = try make()
        labels.addTag("Mixing", to: "ott")
        labels.setColor(.amber, for: "ott")
        let again = UserLabels(url: url)
        #expect(again.labels(of: "ott") == PluginLabels(tags: ["Mixing"], color: .amber))
    }

    @Test func emptyLabelsAreDropped() throws {
        let (labels, url, _dir) = try make()
        labels.addTag("Mixing", to: "ott")
        labels.setColor(.mint, for: "ott")
        labels.removeTag("mixing", from: "ott")
        #expect(labels.all["ott"] != nil)                         // the colour is still there
        labels.setColor(nil, for: "ott")
        #expect(labels.all["ott"] == nil)
        let text = String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self)
        #expect(!text.contains("ott"))
    }

    @Test func allTagsCountAndSort() throws {
        let (labels, _, _dir) = try make()
        labels.addTag("Synth", to: "a")
        labels.addTag("synth", to: "b")
        labels.addTag("Bass", to: "a")
        labels.addTag("Drums", to: "c")
        labels.addTag("Synth", to: "c")
        let all = labels.allTags
        #expect(all.map(\.tag) == ["Synth", "Bass", "Drums"])    // most used first, then by name
        #expect(all.map(\.count) == [3, 1, 1])
    }

    @Test func corruptFileIsKeptAside() throws {
        let (_, url, _dir) = try make()
        try Data("{ not json".utf8).write(to: url)
        let labels = UserLabels(url: url)
        #expect(labels.all.isEmpty)
        let bad = url.appendingPathExtension("bad")
        #expect(FileManager.default.fileExists(atPath: bad.path))
        #expect(String(decoding: (try Data(contentsOf: bad)), as: UTF8.self) == "{ not json")
        labels.addTag("New", to: "ott")                          // and the app goes on writing a fresh file
        #expect(UserLabels(url: url).labels(of: "ott").tags == ["New"])
    }

    @Test func exportIncludesTags() throws {
        let row = ExportRow(name: "OTT", vendor: "Xfer", version: "1", status: "ok", formats: ["VST3"], archs: ["arm64"],
                            sizeBytes: 1, tags: ["Mixing", "Drums, kick"])
        let csv = CatalogExport.render([row], as: .csv).components(separatedBy: "\r\n")
        #expect(csv[0].hasSuffix(",tags"))
        #expect(csv[1].hasSuffix(",\"Drums, kick;Mixing\""))
        #expect(CatalogExport.render([row], as: .markdown).contains("| Drums, kick, Mixing |"))
        let decoded = try JSONDecoder().decode([ExportRow].self, from: Data(CatalogExport.render([row], as: .json).utf8))
        #expect(decoded.first?.tags == ["Drums, kick", "Mixing"])
    }
}
