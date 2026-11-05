import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Mach-O architectures")
struct ArchTests {
    private func archs(_ data: Data) throws -> [String] {
        let dir = try TempDir()
        let url = dir.path("binary")
        try data.write(to: url)
        return PluginInventory.archs(url)
    }

    @Test func universal() throws {
        #expect(try archs(MachO.fat([MachO.x86_64, MachO.arm64])) == ["x86_64", "arm64"])
    }

    @Test func thin() throws {
        #expect(try archs(MachO.thin(MachO.arm64)) == ["arm64"])
        #expect(try archs(MachO.thin(MachO.x86_64)) == ["x86_64"])
        #expect(try archs(MachO.thin(MachO.i386)) == ["i386"])
    }

    @Test func notMachO() throws {
        #expect(try archs(Data("#!/bin/sh\necho hi\n".utf8)).isEmpty)
        #expect(try archs(Data([0xCA, 0xFE])).isEmpty)
    }
}

@Suite("Plugin inventory")
struct InventoryTests {
    let dir: TempDir

    init() throws {
        dir = try TempDir()
        try makeBundle(dir.path("VST3/FabFilter/FabFilter Pro-Q 4.vst3"), id: "com.fabfilter.Pro-Q.4", version: "4.13")
        try makeBundle(dir.path("Components/FabFilter Pro-Q 4.component"), id: "com.fabfilter.Pro-Q.AU.4", extra: [
            "AudioComponents": [["type": "aumf", "subtype": "FQ4p", "manufacturer": "FabF", "name": "FabFilter: Pro-Q 4"]],
        ])
        try makeBundle(dir.path("VST3/Valhalla DSP/ValhallaRoom.vst3"), id: "com.valhalladsp.ValhallaRoom")
        try makeBundle(dir.path("Components/ValhallaRoomAU64.component"), id: "com.valhalladsp.ValhallaRoomAU")
        try makeBundle(dir.path("VST3/Plateau.vst3"), id: "com.example.plateau")
        try makeBundle(dir.path("VST3/Plate.vst3"), id: "com.other.plate")
        try makeBundle(dir.path("VST/OTT.vst"), id: "com.xfer.OTT")
        try makeBundle(dir.path("CLAP/Broken.clap"), id: "com.broken.clap", binary: nil)
    }

    private func scan() -> [ManagedPlugin] { PluginInventory.scan(root: dir.url) }

    @Test func groupsFormatsOfOnePlugin() {
        let proQ = scan().first { $0.name == "FabFilter Pro-Q 4" }
        #expect(proQ?.bundles.map(\.format) == [.au, .vst3])
        #expect(proQ?.version == "4.13" || proQ?.version == "1.0")
    }

    @Test func audioUnitWithAnOddFileNameJoinsByItsOwnName() throws {
        // iZotope ships the AU as "iZOzone11ClarityAUHook.component", named "iZotope: Ozone 11 Clarity" inside
        let root = try TempDir()
        try makeBundle(root.path("VST3/iZotope/Ozone 11 Clarity.vst3"), id: "com.izotope.Ozone11Clarity")
        try makeBundle(root.path("Components/iZOzone11ClarityAUHook.component"), id: "com.izotope.AU.OZONE11CLTY", extra: [
            "AudioComponents": [["type": "aufx", "subtype": "OZCL", "manufacturer": "iZtp", "name": "iZotope: Ozone 11 Clarity"]],
        ])
        let plugins = PluginInventory.scan(root: root.url)
        #expect(plugins.count == 1)
        #expect(plugins.first?.name == "Ozone 11 Clarity")
        #expect(plugins.first?.bundles.count == 2)
    }

    @Test func groupsVendorAUSuffix() {
        let room = scan().first { $0.key.hasPrefix("valhallaroom|") }
        #expect(room?.bundles.map(\.format) == [.au, .vst3])
    }

    @Test func sameNameFromDifferentDevelopersStaysApart() throws {
        try makeBundle(dir.path("VST3/Compressor.vst3"), id: "com.vendora.compressor")
        try makeBundle(dir.path("Components/Compressor.component"), id: "com.vendorb.compressor")
        let compressors = scan().filter { $0.name == "Compressor" }
        #expect(compressors.count == 2)
        #expect(compressors.allSatisfy { $0.bundles.count == 1 })
    }

    @Test func domainPartsMatchTheScript() throws {
        let script = try String(contentsOf: ScriptTests.script, encoding: .utf8)
        let line = try #require(script.split(separator: "\n").first { $0.contains("com|co|uk|") })
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: ")").first?.split(separator: "|").map(String.init)
        #expect(Set(parts ?? []) == PluginInventory.domainParts)
        #expect(PluginInventory.idVendor("jp.co.vendor.Plugin") == "vendor")
        #expect(PluginInventory.idVendor("audio.output.Portal") == "output")
    }

    @Test func keepsSimilarNamesApart() {
        let names = scan().map(\.name)
        #expect(names.contains("Plateau"))
        #expect(names.contains("Plate"))
    }

    @Test func vendorComesFromFolderAUOrBundleID() {
        let plugins = scan()
        #expect(plugins.first { $0.key.hasPrefix("valhallaroom|") }?.vendor == "Valhalla DSP")  // vendor folder
        let au = plugins.flatMap(\.bundles).first { $0.format == .au && $0.url.lastPathComponent.hasPrefix("FabFilter") }
        #expect(au?.vendor == "FabFilter")                                                 // AU component name
        #expect(plugins.first { $0.name == "OTT" }?.vendor == "xfer")                      // bundle id
    }

    @Test func readsAudioUnitCodesAndNesting() throws {
        let bundles = scan().flatMap(\.bundles)
        let au = try #require(bundles.first { $0.url.lastPathComponent == "FabFilter Pro-Q 4.component" })
        #expect(au.au == AUCode(type: "aumf", subtype: "FQ4p", manufacturer: "FabF"))
        #expect(!au.nested)
        let vst3 = try #require(bundles.first { $0.url.lastPathComponent == "FabFilter Pro-Q 4.vst3" })
        #expect(vst3.nested)
        #expect(vst3.displayPath == "VST3/FabFilter/FabFilter Pro-Q 4.vst3")
        #expect(vst3.archs == ["x86_64", "arm64"])
    }

    @Test func missingBinaryFailsTheCheck() throws {
        let broken = try #require(scan().flatMap(\.bundles).first { $0.format == .clap })
        #expect(broken.executable == nil)
        #expect(PluginChecker.check(broken) == [.noBinary])
    }

    @Test func disabledBundleIsFoundAndGroupedWithItsPlugin() throws {
        let root = try TempDir()
        try makeBundle(root.path("VST3/Xfer/X.vst3"), id: "com.xfer.X")
        try makeBundle(root.path("Disabled/Components/X.component"), id: "com.xfer.X.au")
        let one = try #require(PluginInventory.scan(root: root.url).first)
        #expect(PluginInventory.scan(root: root.url).count == 1)
        #expect(one.bundles.count == 2)
        #expect(!one.isDisabled)
        #expect(one.activeBundles.map(\.format) == [.vst3])

        let off = try TempDir()
        try makeBundle(off.path("Disabled/Components/X.component"), id: "com.xfer.X.au")
        try makeBundle(off.path("Disabled/VST3/Xfer/X.vst3"), id: "com.xfer.X")
        let plugin = try #require(PluginInventory.scan(root: off.url).first)
        #expect(plugin.isDisabled)
        #expect(plugin.activeBundles.isEmpty)
        let au = try #require(plugin.bundles.first { $0.format == .au })
        #expect(au.isDisabled)
        #expect(au.enabledURL.path.hasSuffix("/" + off.url.lastPathComponent + "/Components/X.component"))
        let vst3 = try #require(plugin.bundles.first { $0.format == .vst3 })
        #expect(vst3.enabledURL.path.hasSuffix("/" + off.url.lastPathComponent + "/VST3/Xfer/X.vst3"))
        #expect(vst3.nested)                                // the vendor folder still counts as one
        #expect(vst3.vendor == "Xfer")
    }

    @Test func enabledURLOfALiveBundleIsItself() throws {
        let bundle = try #require(scan().first { $0.name == "OTT" }?.bundles.first)
        #expect(!bundle.isDisabled)
        #expect(bundle.enabledURL == bundle.url)
    }

    @Test func bundleIDIsRead() throws {
        let proQ = try #require(scan().first { $0.name == "FabFilter Pro-Q 4" })
        #expect(Set(proQ.bundles.map(\.bundleID)) == ["com.fabfilter.Pro-Q.4", "com.fabfilter.Pro-Q.AU.4"])
    }
}

@Suite("Plugin checks without loading")
struct CheckerTests {
    let dir: TempDir

    init() throws { dir = try TempDir() }

    private func bundle(_ path: String, binary: Data?, extra: [String: Any] = [:]) throws -> PluginBundle {
        try makeBundle(dir.path(path), id: "com.test.plugin", binary: binary, extra: extra)
        return try #require(PluginInventory.scan(root: dir.url).flatMap(\.bundles).first { $0.displayPath == path })
    }

    @Test func wrongArchitecture() throws {
        let old = try bundle("VST/Old.vst", binary: MachO.thin(MachO.i386))
        #expect(PluginChecker.check(old) == [.wrongArch(["i386"])])
    }

    @Test func nestedAudioUnitIsNotRegistered() throws {
        let au = try bundle("Components/Vendor/Nested.component", binary: MachO.fat([MachO.x86_64, MachO.arm64]), extra: [
            "AudioComponents": [["type": "aufx", "subtype": "Nest", "manufacturer": "Test", "name": "Test: Nested"]],
        ])
        #expect(PluginChecker.check(au) == [.notRegistered])
    }

    @Test func quarantineIsReportedAlongsideOtherIssues() throws {
        let url = dir.path("VST3/Downloaded.vst3")
        try makeBundle(url, id: "com.test.dl", binary: nil)
        let value = "0083;00000000;Safari;"
        _ = value.withCString { setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
        let downloaded = try #require(PluginInventory.scan(root: dir.url).flatMap(\.bundles).first)
        #expect(PluginChecker.check(downloaded) == [.quarantined, .noBinary])
    }

    @Test func levels() {
        #expect(CheckState.done([]).level == .ok)
        #expect(CheckState.done([.quarantined]).level == .warning)
        #expect(CheckState.done([.quarantined, .noBinary]).level == .failed)
        #expect(CheckState.unchecked.level == nil)
    }
}

@Suite("Plugins that aren't trusted yet")
struct QuarantineTests {
    @Test func aQuarantinedPluginIsNeverLoaded() throws {
        let dir = try TempDir()
        let url = try makeBundle(dir.path("New.vst3"), id: "com.x.new")
        let bundle = PluginBundle(url: url, format: .vst3, vendor: "x", version: "1", executable: url.appendingPathComponent("Contents/MacOS/New"),
                                  archs: [PluginInventory.hostArch], quarantined: true, au: nil, nested: false)
        #expect(PluginChecker.check(bundle) == [.quarantined])
    }

    @Test func aQuarantinedAudioUnitIsNotValidated() throws {
        let dir = try TempDir()
        let url = try makeBundle(dir.path("New.component"), id: "com.x.new")
        let bundle = PluginBundle(url: url, format: .au, vendor: "x", version: "1", executable: url.appendingPathComponent("Contents/MacOS/New"),
                                  archs: [PluginInventory.hostArch], quarantined: true,
                                  au: AUCode(type: "aufx", subtype: "abcd", manufacturer: "Xxxx"), nested: false)
        #expect(PluginChecker.check(bundle) == [.quarantined])
    }
}
