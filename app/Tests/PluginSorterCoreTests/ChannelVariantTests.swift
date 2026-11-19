import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Mono and Stereo versions are one plugin")
struct ChannelVariantTests {
    private func entry(_ name: String, vendor: String = "Waves", format: String = "VST3") -> InstalledEntry {
        InstalledEntry(fst: URL(fileURLWithPath: "/db/Installed/Effects/\(format)/\(name).fst"), section: "Effects",
                       format: format, name: name, vendor: vendor, files: [])
    }

    private func rows(_ entries: [InstalledEntry]) -> [CatalogRow] {
        PluginCatalog.rows(plugins: [], entries: entries, favorites: [], removed: [])
    }

    @Test func theChannelIsSplitOffTheName() {
        #expect(ChannelVariant.split("C4 Mono") == ("C4", "Mono"))
        #expect(ChannelVariant.split("Doubler2 Mono-Stereo") == ("Doubler2", "Mono-Stereo"))
        #expect(ChannelVariant.split("Silk Vocal Live Stereo") == ("Silk Vocal Live", "Stereo"))
        #expect(ChannelVariant.split("Stereo") == ("Stereo", nil))
        #expect(ChannelVariant.split("OTT") == ("OTT", nil))
    }

    @Test func monoAndStereoMakeOneRowNamedWithoutTheChannel() {
        let rows = rows([entry("C4 Mono"), entry("C4 Stereo"), entry("C4 Stereo", format: "New")])
        #expect(rows.count == 1)
        #expect(rows[0].name == "C4")
        #expect(rows[0].variants == ["Mono", "Stereo"])
        #expect(rows[0].entries.count == 3)
    }

    @Test func variantsAreListedMonoStereoThenBoth() {
        let rows = rows([entry("H-Delay Mono-Stereo"), entry("H-Delay Stereo"), entry("H-Delay Mono")])
        #expect(rows.map(\.variants) == [["Mono", "Stereo", "Mono-Stereo"]])
    }

    @Test func aLiveVersionStaysAPluginOfItsOwn() {
        let rows = rows([entry("Silk Vocal Mono"), entry("Silk Vocal Stereo"),
                         entry("Silk Vocal Live Mono"), entry("Silk Vocal Live Stereo")])
        #expect(rows.map(\.name) == ["Silk Vocal", "Silk Vocal Live"])
    }

    @Test func aSingleChannelKeepsItsFullName() {
        let rows = rows([entry("COSMOS Sample Finder Stereo")])
        #expect(rows.map(\.name) == ["COSMOS Sample Finder Stereo"])
        #expect(rows[0].variants.isEmpty)
    }

    @Test func theSameNameFromAnotherVendorIsNotJoined() {
        let rows = rows([entry("Delay Mono", vendor: "A"), entry("Delay Stereo", vendor: "B")])
        #expect(rows.count == 2)
    }

    @Test func thePictureIsTheStereoOneThenTheOthers() {
        let row = rows([entry("C4 Mono"), entry("C4 Stereo")])[0]
        #expect(row.pictureKeys == ["waves|c4stereo", "waves|c4mono"])
    }

    @Test func theStarPicksStereoFirst() {
        let entries = [entry("C4 Mono"), entry("C4 Mono-Stereo"), entry("C4 Stereo")]
        #expect(entries.sorted { ChannelVariant.rank($0) < ChannelVariant.rank($1) }.first?.name == "C4 Stereo")
    }
}
