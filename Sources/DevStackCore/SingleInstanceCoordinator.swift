import AppKit
import Darwin
import Foundation

@MainActor
enum SingleInstanceCoordinator {
    private static var lockFileDescriptor: Int32 = -1

    static func acquire(using store: ProfileStore = ProfileStore()) -> Bool {
        if lockFileDescriptor >= 0 {
            return true
        }

        try? store.ensureRuntimeDirectories()
        let lockURL = store.rootDirectory.appendingPathComponent("app.lock", isDirectory: false)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            return true
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }

        lockFileDescriptor = descriptor
        let pidText = "\(getpid())\n"
        _ = ftruncate(descriptor, 0)
        _ = pidText.withCString { pointer in
            write(descriptor, pointer, strlen(pointer))
        }
        return true
    }

    static func activateExistingInstance() {
        let currentPID = ProcessInfo.processInfo.processIdentifier

        if let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .filter { $0.processIdentifier != currentPID }
            if let existing = apps.first {
                existing.activate(options: [.activateIgnoringOtherApps])
                return
            }
        }

        guard let executablePath = Bundle.main.executablePath ?? CommandLine.arguments.first else {
            return
        }

        let apps = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != currentPID else {
                return false
            }
            return app.executableURL?.path == executablePath
        }
        apps.first?.activate(options: [.activateIgnoringOtherApps])
    }
}
