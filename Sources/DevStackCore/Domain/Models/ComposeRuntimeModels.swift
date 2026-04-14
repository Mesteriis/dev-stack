import Foundation

package struct ComposeRuntimeService: Codable, Sendable {
    package let Name: String?
    package let Service: String?
    package let State: String?
    package let Status: String?

    package init(Name: String?, Service: String?, State: String?, Status: String?) {
        self.Name = Name
        self.Service = Service
        self.State = State
        self.Status = Status
    }

    package var displayName: String {
        Service ?? Name ?? "service"
    }

    package var displayStatus: String {
        Status ?? State ?? "unknown"
    }
}

package struct ComposeRuntimeSnapshot: Codable, Sendable {
    package let configured: Bool
    package let projectName: String
    package let workingDirectory: String
    package let autoDownOnSwitch: Bool
    package let autoUpOnActivate: Bool
    package let runningServices: [ComposeRuntimeService]

    package init(
        configured: Bool,
        projectName: String,
        workingDirectory: String,
        autoDownOnSwitch: Bool,
        autoUpOnActivate: Bool,
        runningServices: [ComposeRuntimeService]
    ) {
        self.configured = configured
        self.projectName = projectName
        self.workingDirectory = workingDirectory
        self.autoDownOnSwitch = autoDownOnSwitch
        self.autoUpOnActivate = autoUpOnActivate
        self.runningServices = runningServices
    }

    package var localContainerMode: LocalContainerMode {
        LocalContainerMode(autoDownOnSwitch: autoDownOnSwitch, autoUpOnActivate: autoUpOnActivate)
    }
}

package struct ServiceRuntimeSnapshot: Codable, Sendable {
    package let name: String
    package let role: String
    package let aliasHost: String
    package let localPort: Int
    package let remoteHost: String
    package let remotePort: Int
    package let tunnelHost: String
    package let envPrefix: String
    package let enabled: Bool
    package let listening: Bool

    package init(
        name: String,
        role: String,
        aliasHost: String,
        localPort: Int,
        remoteHost: String,
        remotePort: Int,
        tunnelHost: String,
        envPrefix: String,
        enabled: Bool,
        listening: Bool
    ) {
        self.name = name
        self.role = role
        self.aliasHost = aliasHost
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.tunnelHost = tunnelHost
        self.envPrefix = envPrefix
        self.enabled = enabled
        self.listening = listening
    }
}

package struct AppSnapshot: Codable, Sendable {
    package let profile: String
    package let configuredDockerContext: String
    package let activeDockerContext: String
    package let tunnelLoaded: Bool
    package let tunnelLabel: String
    package let compose: ComposeRuntimeSnapshot
    package let services: [ServiceRuntimeSnapshot]

    package init(
        profile: String,
        configuredDockerContext: String,
        activeDockerContext: String,
        tunnelLoaded: Bool,
        tunnelLabel: String,
        compose: ComposeRuntimeSnapshot,
        services: [ServiceRuntimeSnapshot]
    ) {
        self.profile = profile
        self.configuredDockerContext = configuredDockerContext
        self.activeDockerContext = activeDockerContext
        self.tunnelLoaded = tunnelLoaded
        self.tunnelLabel = tunnelLabel
        self.compose = compose
        self.services = services
    }
}
