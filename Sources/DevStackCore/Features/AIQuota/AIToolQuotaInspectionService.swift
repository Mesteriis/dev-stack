import Foundation

package enum AIToolQuotaInspectionService {
    static func inspect(_ kind: AIToolKind) -> AIToolQuotaSnapshot {
        AIToolQuotaInspectors.inspect(kind)
    }
}
