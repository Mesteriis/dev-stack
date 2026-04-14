import Foundation

package struct ComposePortBinding: Sendable {
    package let serviceName: String
    package let publishedPort: Int
    package let targetPort: Int?
    package let hostIP: String?
    package let protocolName: String

    package init(serviceName: String, publishedPort: Int, targetPort: Int?, hostIP: String?, protocolName: String) {
        self.serviceName = serviceName
        self.publishedPort = publishedPort
        self.targetPort = targetPort
        self.hostIP = hostIP
        self.protocolName = protocolName
    }
}

package struct ComposeBindMount: Sendable {
    package let serviceName: String
    package let sourcePath: String
    package let targetPath: String
    package let relativeProjectPath: String?
    package let readOnly: Bool

    package init(
        serviceName: String,
        sourcePath: String,
        targetPath: String,
        relativeProjectPath: String?,
        readOnly: Bool
    ) {
        self.serviceName = serviceName
        self.sourcePath = sourcePath
        self.targetPath = targetPath
        self.relativeProjectPath = relativeProjectPath
        self.readOnly = readOnly
    }
}

package struct ComposeNamedVolumeMount: Sendable {
    package let serviceName: String
    package let sourceName: String
    package let targetPath: String

    package init(serviceName: String, sourceName: String, targetPath: String) {
        self.serviceName = serviceName
        self.sourceName = sourceName
        self.targetPath = targetPath
    }
}

package struct ComposeServicePlan: Sendable {
    package let name: String
    package let image: String?
    package let ports: [ComposePortBinding]
    package let bindMounts: [ComposeBindMount]
    package let namedVolumes: [ComposeNamedVolumeMount]

    package init(
        name: String,
        image: String?,
        ports: [ComposePortBinding],
        bindMounts: [ComposeBindMount],
        namedVolumes: [ComposeNamedVolumeMount]
    ) {
        self.name = name
        self.image = image
        self.ports = ports
        self.bindMounts = bindMounts
        self.namedVolumes = namedVolumes
    }
}

package struct ComposePlan: Sendable {
    package let projectName: String
    package let workingDirectory: URL
    package let sourceComposeURLs: [URL]
    package let environmentFiles: [URL]
    package let services: [ComposeServicePlan]
    package let topLevelVolumeNames: [String]
    package let relativeProjectPaths: [String]
    package let unsupportedRemoteBindSources: [String]
    let normalizedData: Data

    var sourceComposeURL: URL {
        sourceComposeURLs[0]
    }

    init(
        projectName: String,
        workingDirectory: URL,
        sourceComposeURLs: [URL],
        environmentFiles: [URL],
        services: [ComposeServicePlan],
        topLevelVolumeNames: [String],
        relativeProjectPaths: [String],
        unsupportedRemoteBindSources: [String],
        normalizedData: Data
    ) {
        self.projectName = projectName
        self.workingDirectory = workingDirectory
        self.sourceComposeURLs = sourceComposeURLs
        self.environmentFiles = environmentFiles
        self.services = services
        self.topLevelVolumeNames = topLevelVolumeNames
        self.relativeProjectPaths = relativeProjectPaths
        self.unsupportedRemoteBindSources = unsupportedRemoteBindSources
        self.normalizedData = normalizedData
    }
}

package struct ComposeSecretEntry: Sendable {
    package let key: String
    package let statusText: String
    package let envFileURL: URL?
    package let providedByManagedVariables: Bool
    package let hasProfileKeychainValue: Bool
    package let hasProjectKeychainValue: Bool

    package init(
        key: String,
        statusText: String,
        envFileURL: URL?,
        providedByManagedVariables: Bool,
        hasProfileKeychainValue: Bool,
        hasProjectKeychainValue: Bool
    ) {
        self.key = key
        self.statusText = statusText
        self.envFileURL = envFileURL
        self.providedByManagedVariables = providedByManagedVariables
        self.hasProfileKeychainValue = hasProfileKeychainValue
        self.hasProjectKeychainValue = hasProjectKeychainValue
    }
}

package struct ComposeSecretOverview: Sendable {
    package let workingDirectory: URL
    package let environmentFiles: [URL]
    package let referencedKeys: [String]
    package let entries: [ComposeSecretEntry]
    package let profileServiceName: String
    package let projectServiceName: String

    package init(
        workingDirectory: URL,
        environmentFiles: [URL],
        referencedKeys: [String],
        entries: [ComposeSecretEntry],
        profileServiceName: String,
        projectServiceName: String
    ) {
        self.workingDirectory = workingDirectory
        self.environmentFiles = environmentFiles
        self.referencedKeys = referencedKeys
        self.entries = entries
        self.profileServiceName = profileServiceName
        self.projectServiceName = projectServiceName
    }
}

package struct ComposeEnvironmentEntry: Sendable {
    package let key: String
    package let statusText: String
    package let envFileURL: URL?
    package let envFileValue: String?
    package let suggestedWriteURL: URL?
    package let providedByManagedVariables: Bool
    package let hasProfileKeychainValue: Bool
    package let hasProjectKeychainValue: Bool
    package let isMarkedExternal: Bool
    package let isMissing: Bool
    package let isEmptyValue: Bool

    package init(
        key: String,
        statusText: String,
        envFileURL: URL?,
        envFileValue: String?,
        suggestedWriteURL: URL?,
        providedByManagedVariables: Bool,
        hasProfileKeychainValue: Bool,
        hasProjectKeychainValue: Bool,
        isMarkedExternal: Bool,
        isMissing: Bool,
        isEmptyValue: Bool
    ) {
        self.key = key
        self.statusText = statusText
        self.envFileURL = envFileURL
        self.envFileValue = envFileValue
        self.suggestedWriteURL = suggestedWriteURL
        self.providedByManagedVariables = providedByManagedVariables
        self.hasProfileKeychainValue = hasProfileKeychainValue
        self.hasProjectKeychainValue = hasProjectKeychainValue
        self.isMarkedExternal = isMarkedExternal
        self.isMissing = isMissing
        self.isEmptyValue = isEmptyValue
    }
}

package struct ComposeEnvironmentOverview: Sendable {
    package let workingDirectory: URL
    package let profileEnvironmentFile: URL
    package let environmentFiles: [URL]
    package let referencedKeys: [String]
    package let entries: [ComposeEnvironmentEntry]
    package let profileServiceName: String
    package let projectServiceName: String

    package init(
        workingDirectory: URL,
        profileEnvironmentFile: URL,
        environmentFiles: [URL],
        referencedKeys: [String],
        entries: [ComposeEnvironmentEntry],
        profileServiceName: String,
        projectServiceName: String
    ) {
        self.workingDirectory = workingDirectory
        self.profileEnvironmentFile = profileEnvironmentFile
        self.environmentFiles = environmentFiles
        self.referencedKeys = referencedKeys
        self.entries = entries
        self.profileServiceName = profileServiceName
        self.projectServiceName = projectServiceName
    }
}
