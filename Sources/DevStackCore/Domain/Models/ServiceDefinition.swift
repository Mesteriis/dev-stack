import Foundation

package struct ServiceDefinition: Codable, Equatable, Sendable {
    package var name = ""
    package var role = "generic"
    package var aliasHost = ""
    package var localPort = 0
    package var remoteHost = "127.0.0.1"
    package var remotePort = 0
    package var tunnelHost = ""
    package var enabled = true
    package var envPrefix = ""
    package var extraExports: [String] = []

    package var remoteServer: String {
        get { tunnelHost }
        set { tunnelHost = newValue }
    }

    package init(
        name: String = "",
        role: String = "generic",
        aliasHost: String = "",
        localPort: Int = 0,
        remoteHost: String = "127.0.0.1",
        remotePort: Int = 0,
        tunnelHost: String = "",
        enabled: Bool = true,
        envPrefix: String = "",
        extraExports: [String] = []
    ) {
        self.name = name
        self.role = role
        self.aliasHost = aliasHost
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.tunnelHost = tunnelHost
        self.enabled = enabled
        self.envPrefix = envPrefix
        self.extraExports = extraExports
    }
}
