import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Old versions and duplicates")
struct CleanupTests {
    private func bundle(_ path: String, version: String = "1.0", vendor: String = "Vendor", nested: Bool = false,
                        disabled: Bool = false, id: String = "") -> PluginBundle {
        let url = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/" + path)
        let format = PluginFormat.allCases.first { $0.fileExtension == url.pathExtension } ?? .vst3
        return PluginBundle(url: url, format: format, vendor: vendor, version: version, executable: nil, archs: [],
                            quarantined: false, au: nil, nested: nested, isDisabled: disabled, bundleID: id)
    }

    private func plugin(_ name: String, vendor: String = "Vendor", _ bundles: [PluginBundle]) -> ManagedPlugin {
        ManagedPlugin(key: name.lowercased() + "|" + vendor.lowercased(), name: name, vendor: vendor, bundles: bundles)
    }

    private func simple(_ name: String, vendor: String = "Vendor", version: String = "1.0") -> ManagedPlugin {
        plugin(name, vendor: vendor, [bundle("VST3/\(vendor)/\(name).vst3", version: version, vendor: vendor, nested: true)])
    }

    @Test func trailingNumberIsTheVersion() {
        #expect(Cleanup.family(of: "FabFilter Pro-Q 4")?.version == 4)
        #expect(Cleanup.family(of: "FabFilter Pro-Q 4")?.base == Cleanup.family(of: "FabFilter Pro-Q 3")?.base)
        #expect(Cleanup.family(of: "Serum2")?.base == "serum")
        #expect(Cleanup.family(of: "Serum2")?.version == 2)
        #expect(Cleanup.family(of: "Mini V3")?.version == 3)
        #expect(Cleanup.family(of: "Mini V3")?.base == "mini")
        #expect(Cleanup.family(of: "Saturn")?.version == 1)
    }

    @Test func modelNumbersAreNotVersions() {
        #expect(Cleanup.family(of: "Jupiter-8")?.version == 1)     // a number after a hyphen belongs to the name
        #expect(Cleanup.family(of: "SSL 4000")?.version == 1)      // more than two digits is not a version
        let found = Cleanup.findings([simple("Jupiter-4"), simple("Jupiter-8")])
        #expect(found.isEmpty)
    }

    @Test func seriesOfModelsAreNotChainedByNumber() {
        for (a, b) in [("Jupiter 4", "Jupiter 8"), ("DX7", "DX11"), ("Model 72", "Model 84"), ("Stage 73", "Stage 88")] {
            #expect(Cleanup.findings([simple(a), simple(b)]).isEmpty, "\(a) / \(b)")
        }
        // Versions that follow each other still are
        #expect(Cleanup.findings([simple("Ozone 9"), simple("Ozone 11")]).map(\.name) == ["Ozone 9"])
        #expect(Cleanup.findings([simple("Pro-Q 3"), simple("Pro-Q 4")]).map(\.name) == ["Pro-Q 3"])
        // A far-away model doesn't take the real versions with it, nor get offered itself
        let mixed = Cleanup.findings([simple("Pro-Q 2"), simple("Pro-Q 3"), simple("Pro-Q 9")])
        #expect(mixed.map(\.name) == ["Pro-Q 2"])
    }

    @Test func olderVersionsPointAtTheNewest() {
        let found = Cleanup.findings([simple("Pro-Q 2"), simple("Pro-Q 3"), simple("Pro-Q 4")])
        #expect(found.map(\.name) == ["Pro-Q 2", "Pro-Q 3"])
        #expect(found.allSatisfy { $0.kind == .olderVersion(newest: "Pro-Q 4") })
        #expect(found.first?.bundles.count == 1)
    }

    @Test func olderVersionTakesEveryFormat() {
        let old = plugin("Pro-Q 3", [bundle("VST3/Vendor/Pro-Q 3.vst3"), bundle("Components/Pro-Q 3.component")])
        let found = Cleanup.findings([old, simple("Pro-Q 4")])
        #expect(found.count == 1)
        #expect(found.first?.bundles.count == 2)
    }

    @Test func sameNameFromDifferentVendorsIsNoChain() {
        #expect(Cleanup.findings([simple("Saturn", vendor: "Fab"), simple("Saturn 2", vendor: "Other")]).isEmpty)
    }

    @Test func firstVersionWithoutNumberJoinsTheChain() {
        let found = Cleanup.findings([simple("Saturn"), simple("Saturn 2")])
        #expect(found.map(\.name) == ["Saturn"])
        #expect(found.first?.kind == .olderVersion(newest: "Saturn 2"))
    }

    @Test func vst2NextToVst3IsLegacy() {
        let both = plugin("OTT", [bundle("VST/OTT.vst"), bundle("VST3/OTT.vst3"), bundle("Components/OTT.component")])
        let found = Cleanup.findings([both])
        #expect(found.count == 1)
        #expect(found.first?.kind == .legacyVST2)
        #expect(found.first?.bundles.map(\.lastPathComponent) == ["OTT.vst"])
    }

    @Test func vst2AloneIsNotLegacy() {
        #expect(Cleanup.findings([plugin("OTT", [bundle("VST/OTT.vst")])]).isEmpty)
    }

    @Test func twoCopiesOfOneFormatKeepTheNewest() {
        let copies = plugin("X", [bundle("VST3/X.vst3", version: "1.0"),
                                  bundle("VST3/V/X.vst3", version: "2.0", nested: true)])
        let found = Cleanup.findings([copies])
        #expect(found.count == 1)
        #expect(found.first?.kind == .extraCopy)
        #expect(found.first?.bundles.map(\.path) == ["/Library/Audio/Plug-Ins/VST3/X.vst3"])
        // 10 is newer than 9 for a person, not for a string
        let tens = plugin("Y", [bundle("VST3/Y.vst3", version: "10.0"), bundle("VST3/V/Y.vst3", version: "9.0", nested: true)])
        #expect(Cleanup.findings([tens]).first?.bundles.map(\.path) == ["/Library/Audio/Plug-Ins/VST3/V/Y.vst3"])
    }

    @Test func equalCopiesKeepTheOneInTheVendorFolder() {
        let copies = plugin("X", [bundle("VST3/X.vst3"), bundle("VST3/V/X.vst3", nested: true)])
        #expect(Cleanup.findings([copies]).first?.bundles.map(\.path) == ["/Library/Audio/Plug-Ins/VST3/X.vst3"])
    }

    @Test func wavesAreLeftAlone() {
        let shells = [plugin("WaveShell1-VST3 17.1", vendor: "Waves", [bundle("VST3/WaveShell1-VST3 17.1.vst3", id: "com.WavesAudio.WaveShell1-VST3.17.1")]),
                      plugin("WaveShell1-VST3 17.2", vendor: "Waves", [bundle("VST3/WaveShell1-VST3 17.2.vst3", id: "com.WavesAudio.WaveShell1-VST3.17.2")])]
        #expect(Cleanup.findings(shells).isEmpty)
        let twice = plugin("WaveShell1-VST3 17.2", vendor: "Waves", [bundle("VST3/WaveShell1-VST3 17.2.vst3"), bundle("VST3/Waves/WaveShell1-VST3 17.2.vst3", nested: true)])
        #expect(Cleanup.findings([twice]).isEmpty)
    }

    @Test func disabledPluginsCountAsInstalled() {
        let off = plugin("Pro-Q 3", [bundle("Disabled/VST3/Vendor/Pro-Q 3.vst3", disabled: true)])
        #expect(Cleanup.findings([off, simple("Pro-Q 4")]).map(\.name) == ["Pro-Q 3"])
        let newest = plugin("Pro-Q 4", [bundle("Disabled/VST3/Vendor/Pro-Q 4.vst3", disabled: true)])
        #expect(Cleanup.findings([simple("Pro-Q 3"), newest]).map(\.name) == ["Pro-Q 3"])
    }

    @Test func aDisabledCopyIsNotAnExtraCopy() {
        let kept = plugin("X", [bundle("VST3/X.vst3", version: "2.0"),
                                bundle("Disabled/VST3/X.vst3", version: "1.0", disabled: true)])
        #expect(Cleanup.findings([kept]).isEmpty)
    }

    @Test func anOlderVersionIsNotAlsoReportedAsLegacy() {
        let old = plugin("Pro-Q 3", [bundle("VST/Pro-Q 3.vst"), bundle("VST3/Pro-Q 3.vst3")])
        let found = Cleanup.findings([old, simple("Pro-Q 4")])
        #expect(found.count == 1)
        #expect(found.first?.bundles.count == 2)
    }
}
