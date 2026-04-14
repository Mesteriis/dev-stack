import AppKit

@MainActor
extension ProfileEditorWindowController {
    func buildProfile() throws -> ProfileDefinition {
        let selectedMode = selectedLocalContainerMode()
        guard let server = selectedRuntimeTarget() else {
            throw ValidationError("Choose or create a runtime target first.")
        }
        let profile = ProfileDefinition(
            name: nameField.stringValue,
            serverName: server.name,
            dockerContext: server.dockerContext,
            tunnelHost: server.remoteDockerServerDisplay,
            shellExports: splitLines(shellExportsTextView.string),
            externalEnvironmentKeys: externalEnvironmentKeys,
            services: services,
            compose: ComposeDefinition(
                projectName: composeProjectField.stringValue,
                workingDirectory: composeWorkingDirectoryField.stringValue,
                sourceFile: composeSourceFile,
                additionalSourceFiles: composeAdditionalSourceFiles,
                autoDownOnSwitch: selectedMode.autoDownOnSwitch,
                autoUpOnActivate: selectedMode.autoUpOnActivate,
                content: composeTextView.string
            )
        )

        return try profile.normalized()
    }

    func splitLines(_ text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Profile Error"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window ?? NSWindow(), completionHandler: nil)
    }

    func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        field.alignment = .right
        return field
    }

    func sectionTitle(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        return field
    }

    func formRow(label text: String, field: NSView) -> NSView {
        let labelField = NSTextField(labelWithString: text)
        labelField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        labelField.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false

        let grid = NSGridView(views: [[labelField, field]])
        grid.column(at: 0).width = 90
        grid.columnSpacing = 12
        return grid
    }

    func button(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }
}
