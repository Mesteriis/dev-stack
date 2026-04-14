import Foundation

package enum ProfileImportService {
    package static func importedServices(from composeURL: URL) throws -> (content: String, services: [ServiceDefinition]) {
        let content = try String(contentsOf: composeURL, encoding: .utf8)
        let services = ComposeSupport.importServices(
            from: content,
            workingDirectory: composeURL.deletingLastPathComponent()
        )
        guard !services.isEmpty else {
            throw ValidationError("No published ports were detected in \(composeURL.lastPathComponent).")
        }
        return (content, services)
    }

    package static func draftProfile(
        from request: ComposeImportRequest,
        store: ProfileStore,
        currentProfileName: String?,
        activeDockerContext: String?,
        dockerContexts: [DockerContextEntry],
        runtimeTargets: [RemoteServerDefinition]
    ) throws -> ProfileDefinition {
        let existingProfile = try? store.loadProfile(named: request.targetProfileName)
        let currentProfile = currentProfileName.flatMap { try? store.loadProfile(named: $0) }
        var profile = existingProfile ?? ProfileDefinition(
            name: request.targetProfileName,
            serverName: existingProfile?.runtimeName
                ?? currentProfile?.runtimeName
                ?? runtimeTargets.first?.name
                ?? "",
            dockerContext: activeDockerContext
                ?? currentProfile?.dockerContext
                ?? dockerContexts.first(where: \.isCurrent)?.name
                ?? "default",
            tunnelHost: existingProfile?.tunnelHost
                ?? currentProfile?.tunnelHost
                ?? "docker",
            shellExports: existingProfile?.shellExports ?? [],
            externalEnvironmentKeys: existingProfile?.externalEnvironmentKeys ?? [],
            services: existingProfile?.services ?? [],
            compose: existingProfile?.compose ?? ComposeDefinition()
        )

        profile.name = request.targetProfileName
        profile.compose.content = request.composeContent
        profile.compose.sourceFile = request.composeURL.path
        profile.compose.additionalSourceFiles = request.composeOverlayURLs.map(\.path)
        profile.compose.workingDirectory = request.composeWorkingDirectory
        if profile.compose.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.compose.projectName = request.composeProjectName
        }

        if request.replaceServices {
            profile.services = request.services
        } else {
            var merged = Dictionary(uniqueKeysWithValues: profile.services.map { ($0.name, $0) })
            for service in request.services {
                merged[service.name] = service
            }
            profile.services = merged.values.sorted { $0.name < $1.name }
        }

        return try profile.normalized()
    }
}
