import AppKit
import Foundation

extension AppDelegate {
    func makeAILimitsMenu() -> NSMenuItem {
        AIMenuBuilder.buildMenu(delegate: self, snapshots: aiToolSnapshots)
    }
}
