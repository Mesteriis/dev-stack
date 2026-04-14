import Foundation

enum ServerWizardService {
    struct ServerDraftInput {
        let name: String
        let transport: RemoteServerTransport
        let dockerContext: String
        let sshHost: String
        let sshPortText: String
        let sshUser: String
        let remoteDataRoot: String
    }

    static func parseTransport(title: String?) -> RemoteServerTransport {
        RemoteServerTransport.allCases.first(where: { $0.title == title }) ?? .ssh
    }

    static func buildServer(from input: ServerDraftInput) throws -> RemoteServerDefinition {
        let port = Int(input.sshPortText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 22
        return try RemoteServerDefinition(
            name: input.name,
            transport: input.transport,
            dockerContext: input.dockerContext,
            sshHost: input.sshHost,
            sshPort: port,
            sshUser: input.sshUser,
            remoteDataRoot: input.remoteDataRoot
        ).normalized()
    }

    static func initialProgressMessage(for server: RemoteServerDefinition) -> String {
        switch server.transport {
        case .local:
            return "Checking local Docker context \(server.dockerContext)…"
        case .ssh:
            return "Checking \(server.remoteDockerServerDisplay) and preparing runtime context \(server.dockerContext)…"
        }
    }

    static func prepareServer(
        _ server: RemoteServerDefinition,
        store: ProfileStore,
        bootstrapIfNeeded: Bool
    ) throws -> RemoteServerPreparationResult {
        try RuntimeController.prepareServer(server: server, store: store, bootstrapIfNeeded: bootstrapIfNeeded)
    }

    static func savePreparedServer(
        _ server: RemoteServerDefinition,
        originalName: String?,
        store: ProfileStore
    ) throws {
        try store.saveRuntime(server, originalName: originalName)
    }

    static func deleteRuntime(named name: String, store: ProfileStore) throws {
        try store.deleteRuntime(named: name)
    }
}
