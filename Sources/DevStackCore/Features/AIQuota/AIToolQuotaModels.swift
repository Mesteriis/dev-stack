import Foundation

enum AIToolKind: String, CaseIterable, Sendable {
    case codex
    case sonnet
    case qwen
    case google

    var title: String {
        switch self {
        case .codex:
            return "Codex"
        case .sonnet:
            return "Sonnet"
        case .qwen:
            return "Qwen"
        case .google:
            return "Google"
        }
    }
}

struct AIToolQuotaSnapshot: Sendable {
    let kind: AIToolKind
    let statusSymbolName: String
    let cliStatus: String
    let authStatus: String
    let quotaStatus: String
    let progressMetrics: [AIToolProgressMetric]
    let highlightLines: [String]
    let detailLines: [String]
    let helpMessage: String
    let helpCommand: String?
}

struct AIToolProgressMetric: Sendable {
    let id: String
    let title: String
    let usedPercent: Double
    let summary: String
    let resetAt: Date?
    let forecastExhaustionAt: Date?
}

struct CodexRateLimitObservation: Sendable {
    let observedAt: Date?
    let primaryUsedPercent: Double?
    let primaryWindowMinutes: Int?
    let primaryResetsAt: Date?
    let secondaryUsedPercent: Double?
    let secondaryWindowMinutes: Int?
    let secondaryResetsAt: Date?
    let hasCredits: Bool?
    let unlimitedCredits: Bool?
    let planType: String?
    let totalTokens: Int?
    let lastTurnTokens: Int?
    let modelContextWindow: Int?
}

struct QwenQuotaObservation: Sendable {
    let observedAt: Date?
    let message: String
}

struct QwenUsageObservation: Sendable {
    let observedAt: Date?
    let promptTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
}

struct ClaudeAuthObservation: Sendable {
    let loggedIn: Bool
    let authMethod: String?
}

struct GoogleAuthObservation: Sendable {
    let activeAccount: String?
}

enum CodexRateMetric {
    case primary
    case secondary
}
