import Foundation

package struct RemoteServerPreparationResult: Sendable {
    package let server: RemoteServerDefinition
    package let remoteOS: String
    let dockerVersion: String
    package let serverVersion: String
}

struct RuntimeDiagnosticsReport: Sendable {
    let errors: [String]
    let warnings: [String]
    let localPortConflicts: [ComposePortBinding]
}

struct ComposeActionPreview: Sendable {
    let plan: ComposePlan
    let diagnostics: RuntimeDiagnosticsReport
    let runningServiceNames: [String]
}

struct ProfileDeletionPlan: Sendable {
    let profileName: String
    let projectName: String
    let runningServiceNames: [String]
    let localDataPath: String?
    let remoteDataPath: String?
    let remoteProjectPath: String?
    let volumes: [String]
}

struct ComposeVolumeRecord: Sendable {
    let name: String
    let mountpoint: String?
    let driver: String?
}

struct CompactMetricsSnapshot: Sendable {
    let summaryLine: String
    let detailLines: [String]
}
