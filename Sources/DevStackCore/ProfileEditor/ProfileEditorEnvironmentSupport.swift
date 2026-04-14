import AppKit

@MainActor
extension ProfileEditorWindowController {
    func textDidChange(_ notification: Notification) {
        guard let object = notification.object as? NSTextView, object == composeTextView else {
            return
        }
        reloadComposeEnvironmentOverview()
    }
}
