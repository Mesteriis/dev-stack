import Foundation

enum RuntimeSharedSupport {
    static func dockerContexts() throws -> [DockerContextEntry] {
        try RuntimeContextSupport.dockerContexts()
    }

    static func currentDockerContext() throws -> String {
        try RuntimeContextSupport.currentDockerContext()
    }

    static func resolvePrimaryServer(for profile: ProfileDefinition, store: ProfileStore) throws -> ResolvedServer {
        try RuntimeContextSupport.resolvePrimaryServer(for: profile, store: store)
    }

    static func resolveServerDefinition(for profile: ProfileDefinition, store: ProfileStore) throws -> RemoteServerDefinition? {
        try RuntimeContextSupport.resolveServerDefinition(for: profile, store: store)
    }

    static func composePS(profile: ProfileDefinition, store: ProfileStore) throws -> [ComposeRuntimeService] {
        try RuntimeComposeSupport.composePS(profile: profile, store: store)
    }

    static func runCompose(
        profile: ProfileDefinition,
        store: ProfileStore,
        subcommand: [String]
    ) -> CommandResult {
        RuntimeComposeSupport.runCompose(profile: profile, store: store, subcommand: subcommand)
    }

    static func composeVolumes(profile: ProfileDefinition, store: ProfileStore) throws -> [ComposeVolumeRecord] {
        try RuntimeComposeSupport.composeVolumes(profile: profile, store: store)
    }

    static func composeContainerIDs(profile: ProfileDefinition, store: ProfileStore) throws -> [String] {
        try RuntimeComposeSupport.composeContainerIDs(profile: profile, store: store)
    }

    static func inspect(server: RemoteServerDefinition) throws -> RemoteServerInspection {
        try RuntimeShellSupport.inspect(server: server)
    }

    static func ensureDockerContextExists(named context: String) throws {
        try RuntimeContextSupport.ensureDockerContextExists(named: context)
    }

    static func upsertDockerContext(for server: RemoteServerDefinition) throws {
        try RuntimeContextSupport.upsertDockerContext(for: server)
    }

    static func dockerInfo(context: String) throws -> String {
        try RuntimeContextSupport.dockerInfo(context: context)
    }

    static func runRemoteShell(on server: RemoteServerDefinition, script: String) -> CommandResult {
        RuntimeShellSupport.runRemoteShell(on: server, script: script)
    }

    static func sshArguments(for server: RemoteServerDefinition) -> [String] {
        RuntimeShellSupport.sshArguments(for: server)
    }

    static func runLocalShell(_ command: String) -> CommandResult {
        RuntimeShellSupport.runLocalShell(command)
    }

    static func shellCommand(executable: String, arguments: [String]) -> String {
        RuntimeShellSupport.shellCommand(executable: executable, arguments: arguments)
    }

    static func parseKeyValueOutput(_ output: String) -> [String: String] {
        RuntimeShellSupport.parseKeyValueOutput(output)
    }

    static func serviceURL(service: ServiceDefinition) -> String {
        RuntimeShellSupport.serviceURL(service: service)
    }

    static func shellQuote(_ value: String) -> String {
        RuntimeShellSupport.shellQuote(value)
    }

    static func nonEmpty(_ text: String) -> String? {
        RuntimeShellSupport.nonEmpty(text)
    }
}
