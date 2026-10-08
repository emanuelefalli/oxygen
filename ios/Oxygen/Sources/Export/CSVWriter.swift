enum CSVWriter {
    static func render(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map(line).joined()
    }

    private static func line(_ fields: [String]) -> String {
        fields.map(escaped).joined(separator: ",") + "\n"
    }

    private static func escaped(_ field: String) -> String {
        let needsQuotes = field.unicodeScalars.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
