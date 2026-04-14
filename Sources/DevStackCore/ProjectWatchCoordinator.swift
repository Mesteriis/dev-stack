import Darwin
import Foundation

final class ProjectWatchCoordinator {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private let queue = DispatchQueue(label: "devstackmenu.project-watch")

    func reconfigure(paths: [URL], onChange: @escaping @Sendable () -> Void) {
        stop()

        let uniquePaths = Array(Set(paths.map { $0.standardizedFileURL.path })).sorted()
        for path in uniquePaths {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else {
                continue
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .extend, .attrib, .link, .revoke],
                queue: queue
            )
            source.setEventHandler(handler: onChange)
            source.setCancelHandler {
                close(descriptor)
            }
            source.resume()
            sources.append(source)
            fileDescriptors.append(descriptor)
        }
    }

    func stop() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
        fileDescriptors.removeAll()
    }
}
