import Foundation

package enum LocalContainerMode: String, CaseIterable, Codable, Sendable {
    case manual
    case startOnActivate
    case stopOnSwitch
    case switchActive

    package init(autoDownOnSwitch: Bool, autoUpOnActivate: Bool) {
        switch (autoDownOnSwitch, autoUpOnActivate) {
        case (false, false):
            self = .manual
        case (false, true):
            self = .startOnActivate
        case (true, false):
            self = .stopOnSwitch
        case (true, true):
            self = .switchActive
        }
    }

    package var autoDownOnSwitch: Bool {
        switch self {
        case .manual, .startOnActivate:
            return false
        case .stopOnSwitch, .switchActive:
            return true
        }
    }

    package var autoUpOnActivate: Bool {
        switch self {
        case .manual, .stopOnSwitch:
            return false
        case .startOnActivate, .switchActive:
            return true
        }
    }

    package var title: String {
        switch self {
        case .manual:
            return "Manual"
        case .startOnActivate:
            return "Start On Activate"
        case .stopOnSwitch:
            return "Stop On Switch"
        case .switchActive:
            return "Switch Active Containers"
        }
    }

    package var summary: String {
        switch self {
        case .manual:
            return "Do not manage local compose containers automatically."
        case .startOnActivate:
            return "Start this profile's local containers when the profile becomes active."
        case .stopOnSwitch:
            return "Stop this profile's local containers when switching away."
        case .switchActive:
            return "Keep one active local compose stack by stopping the previous profile and starting the new one."
        }
    }
}
