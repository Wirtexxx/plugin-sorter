import Foundation

enum ExportFormat: String, CaseIterable {
    case markdown = "md", csv, json
}

/// One line of an exported list. `status` is one of ok, warning, failed, unchecked, disabled, missing.
struct ExportRow: Equatable, Codable {
    let name, vendor, version, status: String
    let formats, archs: [String]
    let sizeBytes: Int64
    /// The user's own tags.
    var tags: [String] = []
}

extension ExportRow {
    /// A list row as the export shows it: what the row's plugin is made of, and how its last check went.
    init(row: CatalogRow, level: CheckState.Level?, sizeBytes: Int64, tags: [String] = []) {
        let bundles = row.plugin?.bundles ?? []
        let status: String
        switch (row.isStale, row.plugin?.isDisabled ?? false, level) {
        case (true, _, _):            status = "missing"
        case (_, true, _):            status = "disabled"
        case (_, _, .ok?):            status = "ok"
        case (_, _, .warning?):       status = "warning"
        case (_, _, .failed?):        status = "failed"
        case (_, _, nil):             status = "unchecked"
        }
        self.init(name: row.name, vendor: row.vendor, version: row.plugin?.version ?? "", status: status,
                  formats: Set(bundles.map(\.format.rawValue)).sorted(), archs: Set(bundles.flatMap(\.archs)).sorted(),
                  sizeBytes: sizeBytes, tags: tags)
    }
}

enum CatalogExport {
    private static let columns = ["name", "vendor", "version", "status", "formats", "archs", "size_bytes", "tags"]

    static func render(_ rows: [ExportRow], as format: ExportFormat) -> String {
        // The same list in the same order always gives the same text
        let rows = rows.map {
            ExportRow(name: $0.name, vendor: $0.vendor, version: $0.version, status: $0.status,
                      formats: $0.formats.sorted(), archs: $0.archs.sorted(), sizeBytes: $0.sizeBytes, tags: $0.tags.sorted())
        }
        switch format {
        case .csv:      return csv(rows)
        case .markdown: return markdown(rows)
        case .json:     return json(rows)
        }
    }

    // MARK: - CSV

    private static func csv(_ rows: [ExportRow]) -> String {
        var lines = [columns.joined(separator: ",")]
        for row in rows {
            let cells: [String] = [row.name, row.vendor, row.version, row.status,
                                   row.formats.joined(separator: ";"), row.archs.joined(separator: ";")]
            lines.append((cells.map(csvCell) + [String(row.sizeBytes), csvCell(row.tags.joined(separator: ";"))]).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Quoted when it has a comma, a quote or a line break. A text a spreadsheet would run as a formula
    /// ("=cmd|…") gets a quote in front, so it stays text.
    private static func csvCell(_ value: String) -> String {
        var text = value
        if let first = text.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) { text = "'" + text }
        guard text.unicodeScalars.contains(where: { ",\"\r\n".unicodeScalars.contains($0) }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Markdown

    private static func markdown(_ rows: [ExportRow]) -> String {
        let titles: [String] = ["Name", "Vendor", "Version", "Status", "Formats", "Archs", "Size (bytes)", "Tags"]
        let dashes: [String] = titles.map { _ in "---" }
        let header: String = "| " + titles.joined(separator: " | ") + " |"
        let separator: String = "| " + dashes.joined(separator: " | ") + " |"
        var lines: [String] = [header, separator]
        for row in rows {
            let cells: [String] = [row.name, row.vendor, row.version, row.status, row.formats.joined(separator: ", "),
                                   row.archs.joined(separator: ", "), String(row.sizeBytes),
                                   row.tags.joined(separator: ", ")]
            let escaped: [String] = cells.map(markdownCell)
            lines.append("| " + escaped.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A pipe would end the cell and a line break the row.
    private static func markdownCell(_ value: String) -> String {
        var text = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "|":                    text += "\\|"
            case "\n", "\r":             text += " "
            default:                     text.unicodeScalars.append(scalar)
            }
        }
        return text
    }

    // MARK: - JSON

    private static func json(_ rows: [ExportRow]) -> String {
        guard !rows.isEmpty else { return "[]" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(rows)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    }
}
