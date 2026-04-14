import DevStackCore
import Darwin
import Foundation

enum DXApplication {
    static func main() -> Int32 {
        do {
            let command = try DXCommandParser.parse(Array(CommandLine.arguments.dropFirst()))
            try run(command)
            return 0
        } catch {
            DXTerminal.printError(error.localizedDescription)
            return 1
        }
    }

    private static func run(_ command: DXCommand) throws {
        let store = ProfileStore()
        try store.ensureRuntimeDirectories()
        try DXWorkflowHandlers.handle(command, store: store)
    }
}

Darwin.exit(DXApplication.main())
