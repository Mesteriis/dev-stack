import Foundation
import Security

package enum EnvironmentValueGeneratorKind: String, CaseIterable, Sendable {
    case secureRandom32
    case secureRandom64
    case uuidV4
    case uuidV7

    package var title: String {
        switch self {
        case .secureRandom32:
            return "Secure Random (32)"
        case .secureRandom64:
            return "Secure Random (64)"
        case .uuidV4:
            return "UUID v4"
        case .uuidV7:
            return "UUID v7"
        }
    }
}

package enum ContextValueGenerator {
    package static func generate(
        kind: EnvironmentValueGeneratorKind,
        now: Date = Date(),
        randomDataProvider: ((Int) throws -> Data)? = nil
    ) throws -> String {
        switch kind {
        case .secureRandom32:
            return try secureRandomString(length: 32, randomDataProvider: randomDataProvider)
        case .secureRandom64:
            return try secureRandomString(length: 64, randomDataProvider: randomDataProvider)
        case .uuidV4:
            return UUID().uuidString.lowercased()
        case .uuidV7:
            return try uuidV7String(now: now, randomDataProvider: randomDataProvider)
        }
    }

    package static func looksSensitive(key: String) -> Bool {
        let normalized = key.uppercased()
        return [
            "SECRET",
            "TOKEN",
            "PASSWORD",
            "PASS",
            "PRIVATE",
            "API_KEY",
            "ACCESS_KEY",
            "SECRET_KEY",
            "DSN",
        ].contains(where: { normalized.contains($0) })
    }

    private static func secureRandomString(
        length: Int,
        randomDataProvider: ((Int) throws -> Data)?
    ) throws -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var result = ""
        result.reserveCapacity(length)

        while result.count < length {
            let data = try randomData(randomDataProvider, count: max(length, 16))
            for byte in data where result.count < length {
                result.append(alphabet[Int(byte) % alphabet.count])
            }
        }

        return result
    }

    private static func uuidV7String(
        now: Date,
        randomDataProvider: ((Int) throws -> Data)?
    ) throws -> String {
        let timestampMilliseconds = UInt64((now.timeIntervalSince1970 * 1_000).rounded(.down))
        let randomBytes = [UInt8](try randomData(randomDataProvider, count: 10))
        var bytes = [UInt8](repeating: 0, count: 16)

        bytes[0] = UInt8((timestampMilliseconds >> 40) & 0xFF)
        bytes[1] = UInt8((timestampMilliseconds >> 32) & 0xFF)
        bytes[2] = UInt8((timestampMilliseconds >> 24) & 0xFF)
        bytes[3] = UInt8((timestampMilliseconds >> 16) & 0xFF)
        bytes[4] = UInt8((timestampMilliseconds >> 8) & 0xFF)
        bytes[5] = UInt8(timestampMilliseconds & 0xFF)
        bytes[6] = 0x70 | (randomBytes[0] & 0x0F)
        bytes[7] = randomBytes[1]
        bytes[8] = 0x80 | (randomBytes[2] & 0x3F)
        bytes[9] = randomBytes[3]
        bytes[10] = randomBytes[4]
        bytes[11] = randomBytes[5]
        bytes[12] = randomBytes[6]
        bytes[13] = randomBytes[7]
        bytes[14] = randomBytes[8]
        bytes[15] = randomBytes[9]

        let groups = [
            bytes[0 ..< 4],
            bytes[4 ..< 6],
            bytes[6 ..< 8],
            bytes[8 ..< 10],
            bytes[10 ..< 16],
        ]

        return groups
            .map { group in group.map { String(format: "%02x", $0) }.joined() }
            .joined(separator: "-")
    }

    private static func randomData(
        _ randomDataProvider: ((Int) throws -> Data)?,
        count: Int
    ) throws -> Data {
        if let randomDataProvider {
            return try randomDataProvider(count)
        }

        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw ValidationError("Failed to generate secure random data.")
        }
        return data
    }
}

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
