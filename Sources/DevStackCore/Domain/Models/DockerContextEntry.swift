import Foundation

package struct DockerContextEntry: Sendable {
    package let name: String
    package let endpoint: String
    package let isCurrent: Bool

    package init(name: String, endpoint: String, isCurrent: Bool) {
        self.name = name
        self.endpoint = endpoint
        self.isCurrent = isCurrent
    }
}
