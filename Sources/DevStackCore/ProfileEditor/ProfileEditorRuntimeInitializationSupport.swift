import AppKit
import Foundation

@MainActor
extension ProfileEditorWindowController {
    func configureFields(with profile: ProfileDefinition?) {
        nameField.stringValue = profile?.name ?? ""
        nameField.target = self
        nameField.action = #selector(refreshComposeEnvironmentAction(_:))
        composeProjectField.stringValue = profile?.compose.projectName ?? ""
        composeWorkingDirectoryField.stringValue = profile?.compose.workingDirectory ?? ""
        composeWorkingDirectoryField.target = self
        composeWorkingDirectoryField.action = #selector(refreshComposeEnvironmentAction(_:))
        composeSourceFile = profile?.compose.sourceFile ?? ""
        composeAdditionalSourceFiles = profile?.compose.additionalSourceFiles ?? []
        shellExportsTextView.string = (profile?.shellExports ?? []).joined(separator: "\n")
        composeTextView.string = profile?.compose.content ?? ""
        composeTextView.delegate = self

        runtimeField.removeAllItems()
        runtimeField.target = self
        runtimeField.action = #selector(runtimeSelectionChanged(_:))
        reloadRuntimeTargets(preferredName: preferredRuntimeName(for: profile))
        runtimeSummaryField.textColor = .secondaryLabelColor
        runtimeSummaryField.maximumNumberOfLines = 0
        updateRuntimeDetails()

        localContainerModeField.removeAllItems()
        localContainerModeField.addItems(withTitles: LocalContainerMode.allCases.map(\.title))
        let selectedMode = profile?.compose.localContainerMode ?? .manual
        localContainerModeField.selectItem(withTitle: selectedMode.title)
        localContainerModeField.target = self
        localContainerModeField.action = #selector(localContainerModeChanged(_:))
        localContainerModeDescription.textColor = .secondaryLabelColor
        updateLocalContainerModeDescription()
        composeSourceField.textColor = .secondaryLabelColor
        composeSourceField.maximumNumberOfLines = 0
        composeOverlaysSummaryField.textColor = .secondaryLabelColor
        composeOverlaysSummaryField.maximumNumberOfLines = 0
        updateComposeSourceDetails()
        updateComposeOverlayDetails()
        configureEnvironmentFields()
        reloadComposeEnvironmentOverview()
    }
}
