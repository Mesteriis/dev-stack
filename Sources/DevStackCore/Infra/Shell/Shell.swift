import Foundation

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ data: Data) {
        lock.lock()
        self.data = data
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

package enum Shell {
    @discardableResult
    package static func run(
        _ launchPath: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        standardInput: Data? = nil
    ) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let stdinPipe = Pipe()
        if standardInput != nil {
            process.standardInput = stdinPipe
        }

        let stdoutQueue = DispatchQueue(label: "devstackmenu.shell.stdout")
        let stderrQueue = DispatchQueue(label: "devstackmenu.shell.stderr")
        let outputGroup = DispatchGroup()
        let stdoutBuffer = LockedDataBuffer()
        let stderrBuffer = LockedDataBuffer()

        do {
            try process.run()
        } catch {
            return CommandResult(
                exitCode: 127,
                stdout: "",
                stderr: error.localizedDescription
            )
        }

        if let standardInput {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: standardInput)
            try? stdinPipe.fileHandleForWriting.close()
        }

        outputGroup.enter()
        stdoutQueue.async {
            stdoutBuffer.set(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            outputGroup.leave()
        }

        outputGroup.enter()
        stderrQueue.async {
            stderrBuffer.set(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            outputGroup.leave()
        }

        process.waitUntilExit()
        outputGroup.wait()

        let stdout = String(
            data: stdoutBuffer.get(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrBuffer.get(),
            encoding: .utf8
        ) ?? ""

        return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
