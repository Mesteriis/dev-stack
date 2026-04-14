import Foundation

package enum AIToolQuotaInspectionFormatting {
    static func statusSymbol(
        installed: Bool,
        isHealthy: Bool,
        authStatus: String,
        quotaStatus: String
    ) -> String {
        let loweredAuth = authStatus.lowercased()
        let loweredQuota = quotaStatus.lowercased()

        if !installed {
            return "xmark.circle"
        }
        if !isHealthy || loweredAuth.contains("required") || loweredQuota.contains("exhausted") {
            return "exclamationmark.triangle"
        }
        return "checkmark.circle"
    }

    static func codexProgressMetrics(
        latest: CodexRateLimitObservation,
        history: [CodexRateLimitObservation]
    ) -> [AIToolProgressMetric] {
        var result: [AIToolProgressMetric] = []

        if let usedPercent = latest.primaryUsedPercent {
            let forecast = codexForecastExhaustion(
                history: history,
                latestResetAt: latest.primaryResetsAt,
                metric: .primary
            )
            result.append(
                AIToolProgressMetric(
                    id: "codex.primary",
                    title: "Primary",
                    usedPercent: usedPercent,
                    summary: codexMetricSummary(
                        title: "Primary",
                        usedPercent: usedPercent,
                        resetAt: latest.primaryResetsAt
                    ),
                    resetAt: latest.primaryResetsAt,
                    forecastExhaustionAt: forecast
                )
            )
        }

        if let usedPercent = latest.secondaryUsedPercent {
            let forecast = codexForecastExhaustion(
                history: history,
                latestResetAt: latest.secondaryResetsAt,
                metric: .secondary
            )
            result.append(
                AIToolProgressMetric(
                    id: "codex.secondary",
                    title: "Secondary",
                    usedPercent: usedPercent,
                    summary: codexMetricSummary(
                        title: "Secondary",
                        usedPercent: usedPercent,
                        resetAt: latest.secondaryResetsAt
                    ),
                    resetAt: latest.secondaryResetsAt,
                    forecastExhaustionAt: forecast
                )
            )
        }

        return result
    }

    static func codexHighlightLines(
        latest: CodexRateLimitObservation,
        metrics: [AIToolProgressMetric]
    ) -> [String] {
        var result: [String] = []

        if let lastTurnTokens = latest.lastTurnTokens {
            result.append("Last turn: \(formatTokenCount(lastTurnTokens)) tokens")
        }

        if let totalTokens = latest.totalTokens {
            if let contextWindow = latest.modelContextWindow, contextWindow > 0 {
                let percent = Int((Double(totalTokens) / Double(contextWindow) * 100).rounded())
                result.append("Context total: \(formatTokenCount(totalTokens)) / \(formatTokenCount(contextWindow)) (\(percent)%)")
            } else {
                result.append("Window total: \(formatTokenCount(totalTokens)) tokens")
            }
        }

        for metric in metrics.prefix(2) {
            if let forecast = metric.forecastExhaustionAt, let resetAt = metric.resetAt, forecast < resetAt {
                result.append("\(metric.title) forecast: ends around \(AIToolQuotaDataService.formatTimestamp(forecast))")
            }
        }

        return result
    }

    static func codexForecastExhaustion(
        history: [CodexRateLimitObservation],
        latestResetAt: Date?,
        metric: CodexRateMetric
    ) -> Date? {
        guard let latestResetAt else {
            return nil
        }

        let matching = history.filter {
            $0.observedAt != nil
                && codexMetricValue(metric, in: $0) != nil
                && matchesResetDate($0, resetAt: latestResetAt, metric: metric)
        }

        guard let latest = matching.last,
              let latestObservedAt = latest.observedAt,
              let latestPercent = codexMetricValue(metric, in: latest)
        else {
            return nil
        }

        let recent = matching.filter {
            guard let observedAt = $0.observedAt else {
                return false
            }
            return latestObservedAt.timeIntervalSince(observedAt) <= 2 * 60 * 60
        }

        guard let first = recent.first,
              let firstObservedAt = first.observedAt,
              let firstPercent = codexMetricValue(metric, in: first)
        else {
            return nil
        }

        let deltaPercent = latestPercent - firstPercent
        let deltaTime = latestObservedAt.timeIntervalSince(firstObservedAt)
        guard deltaPercent > 0.02, deltaTime > 10 * 60 else {
            return nil
        }

        let rate = deltaPercent / deltaTime
        guard rate > 0 else {
            return nil
        }

        let remainingPercent = max(0, 1 - latestPercent)
        let forecast = latestObservedAt.addingTimeInterval(remainingPercent / rate)
        return forecast < latestResetAt ? forecast : nil
    }

    static func qwenQuotaSummary(_ observation: QwenQuotaObservation?) -> String {
        guard let observation else {
            return "No local quota data"
        }
        if let observedAt = observation.observedAt {
            return "Quota exhausted on \(AIToolQuotaDataService.formatTimestamp(observedAt))"
        }
        return "Last known status: quota exhausted"
    }

    static func qwenUsageSummary(_ observation: QwenUsageObservation) -> String {
        var parts: [String] = []
        if let totalTokens = observation.totalTokens {
            parts.append("Last request: \(formatTokenCount(totalTokens))")
        }
        if let promptTokens = observation.promptTokens, let outputTokens = observation.outputTokens {
            parts.append("in \(formatTokenCount(promptTokens)) / out \(formatTokenCount(outputTokens))")
        }
        let base = parts.joined(separator: ", ")
        if let observedAt = observation.observedAt {
            return "\(base) at \(AIToolQuotaDataService.formatTimestamp(observedAt))"
        }
        return base
    }

    static func codexQuotaSummary(_ observation: CodexRateLimitObservation) -> String {
        guard let primaryUsedPercent = observation.primaryUsedPercent,
              let primaryWindowMinutes = observation.primaryWindowMinutes
        else {
            return "No local quota data"
        }

        let percent = formatPercent(primaryUsedPercent)
        if let resetsAt = observation.primaryResetsAt {
            if primaryUsedPercent >= 0.999 {
                return "Primary exhausted, resets \(AIToolQuotaDataService.formatTimestamp(resetsAt))"
            }
            return "Primary \(percent)% / \(primaryWindowMinutes)m, resets \(AIToolQuotaDataService.formatTimestamp(resetsAt))"
        }
        if primaryUsedPercent >= 0.999 {
            return "Primary exhausted"
        }
        return "Primary \(percent)% / \(primaryWindowMinutes)m"
    }

    static func codexSecondarySummary(_ observation: CodexRateLimitObservation) -> String? {
        guard let usedPercent = observation.secondaryUsedPercent,
              let windowMinutes = observation.secondaryWindowMinutes
        else {
            return nil
        }

        let percent = formatPercent(usedPercent)
        if let resetsAt = observation.secondaryResetsAt {
            return "Secondary \(percent)% / \(windowMinutes)m, resets \(AIToolQuotaDataService.formatTimestamp(resetsAt))"
        }
        return "Secondary \(percent)% / \(windowMinutes)m"
    }

    static func codexCreditsSummary(_ observation: CodexRateLimitObservation) -> String? {
        if observation.unlimitedCredits == true {
            return "Credits: unlimited"
        }
        if observation.hasCredits == false {
            return "Credits: unavailable"
        }
        if observation.hasCredits == true {
            return "Credits: available"
        }
        return nil
    }

    static func commandHealth(path: String?, arguments: [String]) -> (
        installed: Bool,
        isHealthy: Bool,
        summary: String,
        detail: String?
    ) {
        guard let path else {
            return (false, false, "Not installed", nil)
        }

        let result = Shell.run(path, arguments: arguments)
        if result.exitCode == 0 {
            let output = firstLine(trimmedOrFallback(result.stdout, fallback: "Installed"))
            return (true, true, output, "Binary: \(path)")
        }

        let problem = trimmedOrFallback(result.stderr, fallback: trimmedOrFallback(result.stdout, fallback: "Command failed"))
        let firstLineText = problem.components(separatedBy: .newlines).first ?? problem
        return (true, false, "Installed but unhealthy", "Binary issue: \(firstLineText)")
    }

    static func formatTokenCount(_ value: Int) -> String {
        let absoluteValue = abs(Double(value))
        let sign = value < 0 ? "-" : ""

        switch absoluteValue {
        case 1_000_000...:
            return "\(sign)\(String(format: "%.1f", absoluteValue / 1_000_000))M"
        case 1_000...:
            return "\(sign)\(String(format: "%.1f", absoluteValue / 1_000))k"
        default:
            return "\(value)"
        }
    }

    static func trimmedOrFallback(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func firstLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).first ?? text
    }

    private static func codexMetricSummary(title: String, usedPercent: Double, resetAt: Date?) -> String {
        let percent = formatPercent(usedPercent)
        if let resetAt {
            return "\(title): \(percent)% used, resets \(AIToolQuotaDataService.formatTimestamp(resetAt))"
        }
        return "\(title): \(percent)% used"
    }

    private static func codexMetricValue(_ metric: CodexRateMetric, in observation: CodexRateLimitObservation) -> Double? {
        switch metric {
        case .primary:
            return observation.primaryUsedPercent
        case .secondary:
            return observation.secondaryUsedPercent
        }
    }

    private static func matchesResetDate(
        _ observation: CodexRateLimitObservation,
        resetAt: Date,
        metric: CodexRateMetric
    ) -> Bool {
        let observationResetAt: Date?
        switch metric {
        case .primary:
            observationResetAt = observation.primaryResetsAt
        case .secondary:
            observationResetAt = observation.secondaryResetsAt
        }

        guard let observationResetAt else {
            return false
        }
        return abs(observationResetAt.timeIntervalSince(resetAt)) < 1
    }

    private static func formatPercent(_ fraction: Double) -> Int {
        Int((fraction * 100).rounded())
    }
}
