import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Exporting the list")
struct ExportTests {
    private func row(_ name: String = "OTT", vendor: String = "Xfer Records", version: String = "1.37", status: String = "ok",
                     formats: [String] = ["VST3"], archs: [String] = ["arm64"], size: Int64 = 1000) -> ExportRow {
        ExportRow(name: name, vendor: vendor, version: version, status: status, formats: formats, archs: archs, sizeBytes: size)
    }

    private func lines(_ text: String) -> [String] { text.components(separatedBy: "\r\n") }

    @Test func csvHasAHeaderAndCRLF() {
        let csv = CatalogExport.render([row(), row("Serum2")], as: .csv)
        #expect(csv.hasSuffix("\r\n"))
        #expect(!csv.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        let all = lines(csv)
        #expect(all.first == "name,vendor,version,status,formats,archs,size_bytes")
        #expect(all[1] == "OTT,Xfer Records,1.37,ok,VST3,arm64,1000")
        #expect(all.count == 4)                                   // header, two rows, the empty piece after the last CRLF
    }

    @Test func csvQuotesCommasAndQuotes() {
        let csv = CatalogExport.render([row(vendor: "Valhalla DSP, LLC"), row("The \"Big\" One")], as: .csv)
        #expect(csv.contains("\"Valhalla DSP, LLC\""))
        #expect(csv.contains("\"The \"\"Big\"\" One\""))
    }

    @Test func csvKeepsLineBreaksInsideQuotes() {
        let csv = CatalogExport.render([row("Two\nLines")], as: .csv)
        #expect(csv.contains("\"Two\nLines\""))
    }

    @Test func csvDefusesFormulas() {
        let csv = CatalogExport.render([row("=cmd"), row("+1"), row("-1"), row("@SUM(A1)"), row("Fine")], as: .csv)
        for bad in ["'=cmd", "'+1", "'-1", "'@SUM(A1)"] { #expect(csv.contains(bad + ",")) }
        #expect(csv.contains("\r\nFine,"))
        #expect(!csv.contains("\r\n=cmd"))
    }

    @Test func csvListsFormatsSortedAndSizeInBytes() {
        let csv = CatalogExport.render([row(formats: ["VST3", "AU", "CLAP"], archs: ["x86_64", "arm64"], size: 123_456_789)], as: .csv)
        #expect(lines(csv)[1].hasSuffix("AU;CLAP;VST3,arm64;x86_64,123456789"))
    }

    @Test func markdownEscapesPipes() {
        let md = CatalogExport.render([row("A|B")], as: .markdown)
        #expect(md.contains("A\\|B"))
        let table = md.split(separator: "\n").map(String.init)
        #expect(table.count == 3)                                  // header, separator, one row
        #expect(table[0].hasPrefix("| Name |"))
        #expect(table[1].hasPrefix("| --- |"))
        #expect(table[2] == "| A\\|B | Xfer Records | 1.37 | ok | VST3 | arm64 | 1000 |")
    }

    @Test func markdownKeepsARowOnOneLine() {
        let md = CatalogExport.render([row("Two\nLines")], as: .markdown)
        #expect(md.split(separator: "\n").count == 3)
    }

    @Test func jsonRoundTrips() throws {
        let rows = [row(formats: ["AU", "VST3"], archs: ["arm64", "x86_64"]), row("Serum \"2\"", vendor: "Xfer, é", status: "disabled", size: 5)]
        let json = CatalogExport.render(rows, as: .json)
        let decoded = try JSONDecoder().decode([ExportRow].self, from: Data(json.utf8))
        #expect(decoded == rows)
    }

    @Test func jsonSortsFormatsToo() throws {
        let json = CatalogExport.render([row(formats: ["VST3", "AU"])], as: .json)
        let decoded = try JSONDecoder().decode([ExportRow].self, from: Data(json.utf8))
        #expect(decoded.first?.formats == ["AU", "VST3"])
    }

    @Test func emptyListIsStillValid() throws {
        #expect(CatalogExport.render([], as: .csv) == "name,vendor,version,status,formats,archs,size_bytes\r\n")
        #expect(CatalogExport.render([], as: .json) == "[]")
        let md = CatalogExport.render([], as: .markdown)
        #expect(md.split(separator: "\n").count == 2)              // the header and its separator
    }

    // MARK: Status

    private func bundle(_ path: String, disabled: Bool = false) -> PluginBundle {
        let url = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/" + path)
        let format = PluginFormat.allCases.first { $0.fileExtension == url.pathExtension } ?? .vst3
        return PluginBundle(url: url, format: format, vendor: "Xfer", version: "1.37", executable: nil,
                            archs: ["x86_64", "arm64"], quarantined: false, au: nil, nested: false, isDisabled: disabled)
    }

    private func catalogRow(plugin: ManagedPlugin?, stale: Bool = false) -> CatalogRow {
        CatalogRow(id: "ott", name: "OTT", vendor: "Xfer", plugin: plugin, entries: [], favorites: [], isStale: stale)
    }

    @Test func statusComesFromTheCheckDisabledAndMissing() {
        let live = ManagedPlugin(key: "ott", name: "OTT", vendor: "Xfer", bundles: [bundle("VST3/OTT.vst3"), bundle("Components/OTT.component")])
        let off = ManagedPlugin(key: "ott", name: "OTT", vendor: "Xfer", bundles: [bundle("Disabled/VST3/OTT.vst3", disabled: true)])
        func status(_ row: CatalogRow, _ level: CheckState.Level?) -> String {
            ExportRow(row: row, level: level, sizeBytes: 0).status
        }
        #expect(status(catalogRow(plugin: live), .ok) == "ok")
        #expect(status(catalogRow(plugin: live), .warning) == "warning")
        #expect(status(catalogRow(plugin: live), .failed) == "failed")
        #expect(status(catalogRow(plugin: live), nil) == "unchecked")
        #expect(status(catalogRow(plugin: off), nil) == "disabled")
        #expect(status(catalogRow(plugin: nil, stale: true), .failed) == "missing")
    }

    @Test func aRowTakesItsDetailsFromThePlugin() {
        let plugin = ManagedPlugin(key: "ott", name: "OTT", vendor: "Xfer",
                                   bundles: [bundle("VST3/OTT.vst3"), bundle("Components/OTT.component")])
        let exported = ExportRow(row: catalogRow(plugin: plugin), level: .ok, sizeBytes: 42)
        #expect(exported == ExportRow(name: "OTT", vendor: "Xfer", version: "1.37", status: "ok",
                                      formats: ["AU", "VST3"], archs: ["arm64", "x86_64"], sizeBytes: 42))
    }
}
