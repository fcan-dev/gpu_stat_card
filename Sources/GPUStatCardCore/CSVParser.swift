import Foundation

public enum CSVParser {
    /// Extracts the leading numeric token of a field: `"22424 MiB" → "22424"`,
    /// `"103.31 W" → "103.31"`, `"0 %" → "0"`, `"56" → "56"`, `"[N/A]" → ""`.
    public static func numericToken(_ field: String) -> String {
        String(field.prefix { $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" })
    }

    /// Maps one `nvidia-smi --format=csv,noheader` output to a `GPUSample`,
    /// using the first non-empty data line and the 8-column positional layout
    /// documented in the spec. Returns nil on empty input or <8 columns.
    public static func parse(_ csv: String) -> GPUSample? {
        guard let line = csv.split(separator: "\n", omittingEmptySubsequences: true).first else { return nil }
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 8 else { return nil }
        return GPUSample(
            name: fields[0],
            tempC: Int(numericToken(fields[1])),
            fanPct: Int(numericToken(fields[2])),
            vramUsedMiB: Int(numericToken(fields[3])),
            vramTotalMiB: Int(numericToken(fields[4])),
            powerW: Double(numericToken(fields[5])),
            powerLimitW: Double(numericToken(fields[6])),
            utilizationPct: Int(numericToken(fields[7]))
        )
    }
}
