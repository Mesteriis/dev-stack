import Foundation

package struct ComposeDefinition: Codable, Equatable, Sendable {
    package var projectName = ""
    package var workingDirectory = ""
    package var sourceFile = ""
    package var additionalSourceFiles: [String] = []
    package var autoDownOnSwitch = false
    package var autoUpOnActivate = false
    package var content = ""

    package var configured: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    package var localContainerMode: LocalContainerMode {
        get {
            LocalContainerMode(autoDownOnSwitch: autoDownOnSwitch, autoUpOnActivate: autoUpOnActivate)
        }
        set {
            autoDownOnSwitch = newValue.autoDownOnSwitch
            autoUpOnActivate = newValue.autoUpOnActivate
        }
    }

    package init() {}

    package init(
        projectName: String = "",
        workingDirectory: String = "",
        sourceFile: String = "",
        additionalSourceFiles: [String] = [],
        autoDownOnSwitch: Bool = false,
        autoUpOnActivate: Bool = false,
        content: String = ""
    ) {
        self.projectName = projectName
        self.workingDirectory = workingDirectory
        self.sourceFile = sourceFile
        self.additionalSourceFiles = additionalSourceFiles
        self.autoDownOnSwitch = autoDownOnSwitch
        self.autoUpOnActivate = autoUpOnActivate
        self.content = content
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName) ?? ""
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory) ?? ""
        sourceFile = try container.decodeIfPresent(String.self, forKey: .sourceFile) ?? ""
        additionalSourceFiles = try container.decodeIfPresent([String].self, forKey: .additionalSourceFiles) ?? []
        autoDownOnSwitch = try container.decodeIfPresent(Bool.self, forKey: .autoDownOnSwitch) ?? false
        autoUpOnActivate = try container.decodeIfPresent(Bool.self, forKey: .autoUpOnActivate) ?? false
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
    }
}
