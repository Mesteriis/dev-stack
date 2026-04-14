import Foundation

package enum RuntimeController {
    package static func dockerContexts() throws -> [DockerContextEntry] {
        try RuntimeStatusService.dockerContexts()
    }

    static func remoteServers(store: ProfileStore) throws -> [RemoteServerDefinition] {
        try RuntimeStatusService.remoteServers(store: store)
    }

    package static func currentDockerContext() throws -> String {
        try RuntimeStatusService.currentDockerContext()
    }

    static func cleanupProfilesWithMissingComposeSources(store: ProfileStore) throws -> [String] {
        try RuntimeStatusService.cleanupProfilesWithMissingComposeSources(store: store)
    }

    package static func previewManagedDataRewrite(
        content: String,
        dataRootPath: String
    ) -> (content: String, serviceNames: [String]) {
        RemoteSyncService.previewManagedDataRewrite(content: content, dataRootPath: dataRootPath)
    }

    package static func prepareServer(
        server: RemoteServerDefinition,
        store: ProfileStore,
        bootstrapIfNeeded: Bool
    ) throws -> RemoteServerPreparationResult {
        try RuntimeLifecycleService.prepareServer(server: server, store: store, bootstrapIfNeeded: bootstrapIfNeeded)
    }

    package static func statusSnapshot(store: ProfileStore, profileName: String) throws -> AppSnapshot {
        try RuntimeStatusService.statusSnapshot(store: store, profileName: profileName)
    }

    package static func activateProfile(named profileName: String, store: ProfileStore) throws {
        try RuntimeLifecycleService.activateProfile(named: profileName, store: store)
    }

    package static func stopProfile(named profileName: String, store: ProfileStore) throws {
        try RuntimeLifecycleService.stopProfile(named: profileName, store: store)
    }

    static func restartProfile(named profileName: String, store: ProfileStore) throws {
        try RuntimeLifecycleService.restartProfile(named: profileName, store: store)
    }

    static func composeUp(profileName: String, store: ProfileStore) throws {
        try RuntimeLifecycleService.composeUp(profileName: profileName, store: store)
    }

    static func composeDown(profileName: String, store: ProfileStore) throws {
        try RuntimeLifecycleService.composeDown(profileName: profileName, store: store)
    }

    static func composeRestart(profileName: String, store: ProfileStore) throws {
        try RuntimeLifecycleService.composeRestart(profileName: profileName, store: store)
    }

    static func deleteProfile(named profileName: String, store: ProfileStore, removeData: Bool) throws {
        try RuntimeDeletionService.deleteProfile(named: profileName, store: store, removeData: removeData)
    }

    static func cleanupRuntime(for profile: ProfileDefinition, store: ProfileStore, removeVolumes: Bool) throws {
        try RuntimeLifecycleService.cleanupRuntime(for: profile, store: store, removeVolumes: removeVolumes)
    }

    static func shellExports(profileName: String, store: ProfileStore) throws -> String {
        try RuntimeLifecycleService.shellExports(profileName: profileName, store: store)
    }

    static func activeProfileNames(store: ProfileStore) -> [String] {
        RuntimeStatusService.activeProfileNames(store: store)
    }

    static func composePreview(profileName: String, store: ProfileStore) throws -> ComposeActionPreview {
        try RuntimeReportService.composePreview(profileName: profileName, store: store)
    }

    static func deletionPlan(profileName: String, store: ProfileStore, removeData: Bool) throws -> ProfileDeletionPlan {
        try RuntimeDeletionService.deletionPlan(profileName: profileName, store: store, removeData: removeData)
    }

    static func writeComposeLogsSnapshot(profileName: String, store: ProfileStore) throws -> URL {
        try RuntimeReportService.writeComposeLogsSnapshot(profileName: profileName, store: store)
    }

    static func writeVolumeReport(profileName: String, store: ProfileStore) throws -> URL {
        try RuntimeReportService.writeVolumeReport(profileName: profileName, store: store)
    }

    static func removeComposeVolumes(profileName: String, store: ProfileStore) throws -> [String] {
        try RuntimeDeletionService.removeComposeVolumes(profileName: profileName, store: store)
    }

    static func writeMetricsReport(profileName: String, store: ProfileStore) throws -> URL {
        try RuntimeReportService.writeMetricsReport(profileName: profileName, store: store)
    }

    static func compactMetrics(profileName: String, store: ProfileStore) throws -> CompactMetricsSnapshot {
        try RuntimeReportService.compactMetrics(profileName: profileName, store: store)
    }

    static func writeRemoteBrowseReport(profileName: String, store: ProfileStore) throws -> URL {
        try RuntimeReportService.writeRemoteBrowseReport(profileName: profileName, store: store)
    }
}
