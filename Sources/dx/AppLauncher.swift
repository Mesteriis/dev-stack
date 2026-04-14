import AppKit

enum DXAppBridge {
    static func openDevStackMenu() {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: "local.devstackmenu.app").first {
            running.activate(options: [.activateIgnoringOtherApps])
            return
        }

        let appURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/DevStackMenu.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: appURL.path) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration, completionHandler: nil)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open", isDirectory: false)
        process.arguments = ["-a", "DevStackMenu"]
        try? process.run()
    }
}
