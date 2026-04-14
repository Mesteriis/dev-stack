import Foundation

package enum AIToolQuotaInspector {
    static func collectAll(forceRefresh: Bool = false) -> [AIToolQuotaSnapshot] {
        _ = forceRefresh
        return AIToolKind.allCases.map(inspect)
    }

    static func invalidateCache() {
        // No-op. Tool status is recomputed on each refresh.
    }

    package static func parseCodexRateLimitEvent(from line: String) -> (
        primaryUsedPercent: Double?,
        primaryWindowMinutes: Int?,
        primaryResetsAt: Date?
    )? {
        AIToolQuotaDataService.parseCodexRateLimitEvent(from: line)
    }

    package static func parseTimestampedQuotaIssue(from line: String) -> Date? {
        AIToolQuotaDataService.parseTimestampedQuotaIssue(from: line)
    }

    private static func inspect(_ kind: AIToolKind) -> AIToolQuotaSnapshot {
        AIToolQuotaInspectionService.inspect(kind)
    }
}
