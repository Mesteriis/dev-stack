import Foundation

package enum ComposeSupport {
    package static func plan(profile: ProfileDefinition, store: ProfileStore) throws -> ComposePlan {
        try ComposePlanBuilder.plan(profile: profile, store: store)
    }

    package static func generatedComposeFile(
        profile: ProfileDefinition,
        store: ProfileStore,
        server: RemoteServerDefinition?
    ) throws -> (composeURL: URL, plan: ComposePlan) {
        try ComposeFileGenerationService.generatedComposeFile(profile: profile, store: store, server: server)
    }

    package static func renderedComposeYAML(from normalizedObject: [String: Any]) throws -> Data {
        try ComposeFileGenerationService.renderedComposeYAML(from: normalizedObject)
    }

    package static func importServices(from content: String, workingDirectory: URL?) -> [ServiceDefinition] {
        ComposePlanBuilder.importServices(from: content, workingDirectory: workingDirectory)
    }

    package static func writePlanReport(plan: ComposePlan, to url: URL) throws {
        try ComposePreviewFormatter.writePlanReport(plan: plan, to: url)
    }

    package static func planReport(plan: ComposePlan) -> String {
        ComposePreviewFormatter.planReport(plan: plan)
    }

    package static func parseEnvironmentFile(at url: URL) -> [String: String] {
        ComposeEnvironmentService.parseEnvironmentFile(at: url)
    }

    package static func parseEnvironmentText(_ text: String) -> [String: String] {
        ComposeEnvironmentService.parseEnvironmentText(text)
    }

    package static func secretOverview(profile: ProfileDefinition, store: ProfileStore) throws -> ComposeSecretOverview {
        try ComposeSecretSupport.secretOverview(profile: profile, store: store)
    }

    package static func saveProfileSecret(key: String, value: String, profile: ProfileDefinition) throws {
        try ComposeSecretSupport.saveProfileSecret(key: key, value: value, profile: profile)
    }

    package static func deleteProfileSecret(key: String, profile: ProfileDefinition) throws {
        try ComposeSecretSupport.deleteProfileSecret(key: key, profile: profile)
    }

    package static func environmentOverview(
        profile: ProfileDefinition,
        store: ProfileStore,
        ignoredKeys: Set<String> = []
    ) throws -> ComposeEnvironmentOverview {
        try ComposeEnvironmentService.environmentOverview(
            profile: profile,
            store: store,
            ignoredKeys: ignoredKeys
        )
    }

    package static func saveEnvironmentValue(
        key: String,
        value: String,
        profile: ProfileDefinition,
        store: ProfileStore,
        fileURL: URL?
    ) throws {
        try ComposeEnvironmentService.saveEnvironmentValue(
            key: key,
            value: value,
            profile: profile,
            store: store,
            fileURL: fileURL
        )
    }

    package static func applicableManagedVariables(
        profile: ProfileDefinition,
        store: ProfileStore
    ) throws -> [ManagedVariableDefinition] {
        try ComposeEnvironmentService.applicableManagedVariables(profile: profile, store: store)
    }

    package static func referencedEnvironmentKeys(in text: String) -> Set<String> {
        ComposeEnvironmentService.referencedEnvironmentKeys(in: text)
    }
}
