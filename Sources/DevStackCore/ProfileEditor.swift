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

}
