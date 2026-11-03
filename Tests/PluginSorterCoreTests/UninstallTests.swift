import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Uninstall with leftovers")
struct UninstallTests {
    private let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)

    private func bundle(_ path: String, id: String = "") -> PluginBundle {
        let url = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/" + path)
        let format = PluginFormat.allCases.first { $0.fileExtension == url.pathExtension } ?? .vst3
        return PluginBundle(url: url, format: format, vendor: "Xfer Records", version: "1.0", executable: nil, archs: [],
                            quarantined: false, au: nil, nested: path.split(separator: "/").count > 2, bundleID: id)
    }

    private func plugin(_ name: String, vendor: String = "Xfer Records", id: String = "", formats: [String] = ["vst3"]) -> ManagedPlugin {
        let bundles = formats.map { bundle(($0 == "component" ? "Components/" : "VST3/\(vendor)/") + "\(name).\($0)", id: id) }
        return ManagedPlugin(key: name.lowercased() + "|" + vendor.lowercased(), name: name, vendor: vendor, bundles: bundles)
    }

    private func leftovers(for target: ManagedPlugin, others: [ManagedPlugin] = [], folders: [String] = [],
                           existing: Set<String> = []) -> [Leftover] {
        Uninstall.leftovers(for: target, others: others, home: home,
                            dataFolders: folders.map { URL(fileURLWithPath: $0, isDirectory: true) },
                            fileExists: { existing.contains($0.path) })
    }

    // MARK: Receipts

    @Test func receiptIsFoundByFileNameAfterSorting() {
        // The installer wrote it at VST3/OTT.vst3; sorting moved the plugin into VST3/Xfer Records/
        let receipt = Receipt(id: "com.xfer.OTT.pkg", files: ["Library/Audio/Plug-Ins/VST3/OTT.vst3/Contents/Info.plist"])
        let other = Receipt(id: "com.other.pkg", files: ["Library/Audio/Plug-Ins/VST3/Other.vst3"])
        let found = Uninstall.receipts(in: [receipt, other], for: plugin("OTT"))
        #expect(found == [receipt])
    }

    @Test func receiptNamesMatchRegardlessOfCase() {
        let receipt = Receipt(id: "a", files: ["Library/Audio/Plug-Ins/VST3/ott.VST3"])
        #expect(Uninstall.receipts(in: [receipt], for: plugin("OTT")).count == 1)
    }

    @Test func aFolderOfTheSameNameIsNotAPlugin() {
        // Only a plugin bundle's name counts, not any file that happens to be called like it
        let receipt = Receipt(id: "a", files: ["Library/Application Support/Xfer/OTT.vst3.txt", "Library/Docs/OTT.vst3x"])
        #expect(Uninstall.receipts(in: [receipt], for: plugin("OTT")).isEmpty)
    }

    @Test func sharedReceiptIsKept() {
        let receipt = Receipt(id: "com.xfer.suite.pkg", files: ["Library/Audio/Plug-Ins/VST3/X.vst3", "Library/Audio/Plug-Ins/VST3/Y.vst3"])
        let x = plugin("X"), y = plugin("Y")
        // Removing X while Y is still installed: the installer's record stays
        #expect(Uninstall.forgettable([receipt], removing: x, others: [y]).isEmpty)
        // Removing the last plugin of the receipt: it goes
        #expect(Uninstall.forgettable([receipt], removing: y, others: []) == [receipt])
        // Every other installed plugin is looked at, however many
        #expect(Uninstall.forgettable([receipt], removing: x, others: [plugin("Z"), y]).isEmpty)
    }

    @Test func receiptsOnlyListBundleRoots() {
        let files = ["Library", "Library/Audio/Plug-Ins/VST3/X.vst3", "Library/Audio/Plug-Ins/VST3/X.vst3/Contents/MacOS/X",
                     "Library/Audio/Plug-Ins/Components/X.component/Contents/Info.plist", "Applications/Y.app/Contents"]
        #expect(Uninstall.bundleRoots(in: files) == ["Library/Audio/Plug-Ins/VST3/X.vst3",
                                                     "Library/Audio/Plug-Ins/Components/X.component"])
    }

    // MARK: Leftovers

    @Test func preferencesAndCachesFoundByBundleId() {
        let target = plugin("OTT", id: "com.xfer.OTT", formats: ["vst3", "component"])
        let existing: Set<String> = ["/Users/test/Library/Preferences/com.xfer.OTT.plist", "/Users/test/Library/Caches/com.xfer.OTT"]
        let found = leftovers(for: target, existing: existing)
        #expect(found.map(\.kind) == [.preferences, .cache])
        #expect(found.map(\.url.path) == ["/Users/test/Library/Preferences/com.xfer.OTT.plist",
                                          "/Users/test/Library/Caches/com.xfer.OTT"])
        #expect(found.allSatisfy { $0.preselected })
        // What isn't there isn't offered
        #expect(leftovers(for: target).isEmpty)
        #expect(leftovers(for: plugin("OTT"), existing: existing).isEmpty)       // no bundle id, nothing to look for
    }

    @Test func presetsMatchedByPluginFolder() {
        let vendorFolder = "/Library/Audio/Presets/Xfer Records"
        let others = [plugin("Serum", id: "com.xfer.Serum")]        // the vendor still has a plugin, so only OTT's own folder
        let found = leftovers(for: plugin("OTT"), others: others, folders: [vendorFolder],
                              existing: [vendorFolder + "/OTT", vendorFolder + "/Y"])
        #expect(found.map(\.url.path) == [vendorFolder + "/OTT"])
        #expect(found.first?.kind == .presets)
    }

    @Test func vendorFolderOfferedOnlyForLastPlugin() {
        let folder = "/Library/Application Support/Xfer Records"
        let serum = plugin("Serum")
        let withOthers = leftovers(for: plugin("OTT"), others: [serum], folders: [folder])
        #expect(!withOthers.contains { $0.kind == .vendorData })
        let last = leftovers(for: plugin("OTT"), others: [plugin("Compressor", vendor: "Fab")], folders: [folder])
        #expect(last.map(\.kind) == [.vendorData])
        #expect(last.first?.url.path == folder)
    }

    @Test func vendorFolderIsNeverPreselected() {
        let folder = "/Library/Application Support/Xfer Records"
        let found = leftovers(for: plugin("OTT"), folders: [folder])
        #expect(found.contains { $0.kind == .vendorData })
        #expect(found.filter { $0.kind == .vendorData }.allSatisfy { !$0.preselected })
    }

    @Test func aPluginFolderInsideTheOfferedVendorFolderIsNotListedTwice() {
        let folder = "/Library/Application Support/Xfer Records"
        let found = leftovers(for: plugin("OTT"), folders: [folder], existing: [folder + "/OTT"])
        #expect(found.map(\.url.path) == [folder])
    }

    @Test func aSimilarVendorNameStillCountsAsTheSameDeveloper() {
        // "Xfer" folder, "Xfer Records" plugins: another Xfer plugin keeps the folder
        let found = leftovers(for: plugin("OTT"), others: [plugin("Serum")], folders: ["/Library/Application Support/Xfer"])
        #expect(!found.contains { $0.kind == .vendorData })
    }
}
