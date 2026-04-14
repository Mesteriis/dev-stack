import AppKit
import Foundation

@MainActor
final class ProfileEditorWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSTextViewDelegate {
    typealias SaveHandler = @MainActor (_ profile: ProfileDefinition, _ originalName: String?) throws -> Void

    let store: ProfileStore
    let originalName: String?
    let dockerContexts: [DockerContextEntry]
    let onSave: SaveHandler
    let onClose: () -> Void

    let nameField = NSTextField()
    let runtimeField = NSPopUpButton()
    let runtimeDockerContextField = NSTextField(labelWithString: "")
    let runtimeRemoteHostField = NSTextField(labelWithString: "")
    let runtimeSummaryField = NSTextField(wrappingLabelWithString: "")
    let composeProjectField = NSTextField()
    let composeWorkingDirectoryField = NSTextField()
    let composeSourceField = NSTextField(wrappingLabelWithString: "")
    let composeOverlaysField = NSPopUpButton()
    let composeOverlaysSummaryField = NSTextField(wrappingLabelWithString: "")
    let localContainerModeField = NSPopUpButton()
    let localContainerModeDescription = NSTextField(wrappingLabelWithString: "")
    let shellExportsTextView = NSTextView()
    let composeTextView = NSTextView()
    let servicesTableView = NSTableView()
    let environmentSummaryField = NSTextField(wrappingLabelWithString: "")
    let environmentTableView = NSTableView()
    let environmentKeyField = NSTextField(labelWithString: "No variable selected")
    let environmentStatusField = NSTextField(wrappingLabelWithString: "")
    let environmentValueField = NSTextField()
    let environmentSensitiveCheckbox = NSButton(checkboxWithTitle: "Save in Keychain", target: nil, action: nil)
    let environmentNoteField = NSTextField(wrappingLabelWithString: "")
    let clipboardPreviewField = NSTextField(wrappingLabelWithString: "")
    var environmentGenerateButton: NSButton?
    var environmentSaveButton: NSButton?
    var environmentIgnoreButton: NSButton?
    var environmentExternalButton: NSButton?
    var clipboardUseButton: NSButton?
    var runtimeTargets: [RemoteServerDefinition]
    var services: [ServiceDefinition]
    var composeSourceFile = ""
    var composeAdditionalSourceFiles: [String] = []
    var environmentOverview: ComposeEnvironmentOverview?
    var externalEnvironmentKeys: [String]
    var ignoredEnvironmentKeys = Set<String>()
    var environmentMessage: String?
    var clipboardParseResult: ClipboardSmartParseResult?
    var clipboardTimer: Timer?
    var lastClipboardChangeCount = NSPasteboard.general.changeCount

    init(
        store: ProfileStore,
        profile: ProfileDefinition?,
        dockerContexts: [DockerContextEntry],
        onSave: @escaping SaveHandler,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.originalName = profile?.name
        self.dockerContexts = dockerContexts
        self.onSave = onSave
        self.onClose = onClose
        self.runtimeTargets = (try? store.runtimeTargets().sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }) ?? []
        self.services = profile?.services ?? []
        self.externalEnvironmentKeys = profile?.externalEnvironmentKeys ?? []

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = profile == nil ? "New DevStack Profile" : "Edit DevStack Profile"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        configureFields(with: profile)
        buildUI()
        startClipboardObservation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        clipboardTimer?.invalidate()
        onClose()
    }

    @objc func beginAddService() {
        addServiceAction(nil)
    }

    @objc func saveAction(_ sender: Any?) {
        do {
            let profile = try buildProfile()
            try onSave(profile, originalName)
            close()
        } catch {
            presentError(error.localizedDescription)
        }
    }

    @objc func cancelAction(_ sender: Any?) {
        close()
    }

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
