import Foundation

func trimmedOrDefault(_ value: String, defaultValue: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? defaultValue : trimmed
}
