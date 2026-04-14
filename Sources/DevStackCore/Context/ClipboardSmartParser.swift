import Foundation

package struct ClipboardSmartParseResult: Equatable, Sendable {
    package let title: String
    package let preview: String
    package let value: String?
}

package enum ClipboardSmartParser {
    package static func parse(_ raw: String) -> ClipboardSmartParseResult? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let timestamp = parseTimestamp(trimmed) {
            return timestamp
        }
        if let json = parseJSON(trimmed) {
            return json
        }
        if let base64 = parseBase64(trimmed) {
            return base64
        }
        return nil
    }

    private static func parseTimestamp(_ text: String) -> ClipboardSmartParseResult? {
        guard text.range(of: #"^\d{10}(\d{3})?$"#, options: .regularExpression) != nil else {
            return nil
        }

        guard let value = Double(text) else {
            return nil
        }

        let seconds = text.count == 13 ? value / 1_000 : value
        let date = Date(timeIntervalSince1970: seconds)
        let iso = ISO8601DateFormatter().string(from: date)
        return ClipboardSmartParseResult(
            title: "Clipboard: Unix timestamp",
            preview: iso,
            value: iso
        )
    }

    private static func parseJSON(_ text: String) -> ClipboardSmartParseResult? {
        guard let first = text.first, first == "{" || first == "[" else {
            return nil
        }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let pretty = String(data: prettyData, encoding: .utf8)
        else {
            return nil
        }

        return ClipboardSmartParseResult(
            title: "Clipboard: JSON",
            preview: compactPreview(pretty),
            value: pretty
        )
    }

    private static func parseBase64(_ text: String) -> ClipboardSmartParseResult? {
        guard text.count >= 12,
              text.count.isMultiple(of: 4),
              text.range(of: #"^[A-Za-z0-9+/]+={0,2}$"#, options: .regularExpression) != nil,
              let data = Data(base64Encoded: text)
        else {
            return nil
        }

        if let decoded = String(data: data, encoding: .utf8),
           isMostlyPrintable(decoded)
        {
            return ClipboardSmartParseResult(
                title: "Clipboard: Base64",
                preview: compactPreview(decoded),
                value: decoded
            )
        }

        return ClipboardSmartParseResult(
            title: "Clipboard: Base64",
            preview: "Decoded \(data.count) bytes",
            value: nil
        )
    }

    private static func compactPreview(_ text: String) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        if singleLine.count <= 140 {
            return singleLine
        }
        return String(singleLine.prefix(137)) + "..."
    }

    private static func isMostlyPrintable(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else {
            return false
        }
        let printable = scalars.filter {
            CharacterSet.whitespacesAndNewlines.contains($0)
                || ($0.value >= 32 && $0.value < 127)
        }
        return Double(printable.count) / Double(scalars.count) >= 0.9
    }
}
