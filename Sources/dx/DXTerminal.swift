import DevStackCore
import Foundation

enum DXTerminal {
    static func requireInteractive() throws {
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
            throw DXCLIError("This command needs an interactive terminal. Run it in a TTY or use non-interactive commands like `dx status` or `dx env check`.")
        }
    }

    static func prompt(
        _ message: String,
        defaultValue: String? = nil,
        allowEmpty: Bool = false
    ) throws -> String {
        while true {
            if let defaultValue, !defaultValue.isEmpty {
                print("\(message) [\(defaultValue)]: ", terminator: "")
            } else {
                print("\(message): ", terminator: "")
            }
            fflush(stdout)

            guard let line = readLine(strippingNewline: true) else {
                throw DXCLIError("Input closed.")
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if let defaultValue {
                    return defaultValue
                }
                if allowEmpty {
                    return ""
                }
                continue
            }
            return trimmed
        }
    }

    static func confirm(_ message: String, defaultYes: Bool = false) throws -> Bool {
        let suffix = defaultYes ? "[Y/n]" : "[y/N]"
        while true {
            print("\(message) \(suffix): ", terminator: "")
            fflush(stdout)
            guard let line = readLine(strippingNewline: true) else {
                throw DXCLIError("Input closed.")
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.isEmpty {
                return defaultYes
            }
            if ["y", "yes"].contains(trimmed) {
                return true
            }
            if ["n", "no"].contains(trimmed) {
                return false
            }
        }
    }

    static func chooseOne<T>(
        title: String,
        options: [T],
        defaultIndex: Int = 0,
        render: (T) -> String
    ) throws -> T {
        guard !options.isEmpty else {
            throw DXCLIError("No options available for \(title).")
        }
        print(title)
        for (index, option) in options.enumerated() {
            let marker = index == defaultIndex ? "*" : " "
            print("  \(marker) \(index + 1). \(render(option))")
        }
        while true {
            let raw = try prompt("Choose 1-\(options.count)", defaultValue: String(defaultIndex + 1))
            if let value = Int(raw), value >= 1, value <= options.count {
                return options[value - 1]
            }
        }
    }

    static func chooseManyURLs(title: String, options: [URL]) throws -> [URL] {
        guard !options.isEmpty else {
            return []
        }
        print(title)
        for (index, option) in options.enumerated() {
            print("  \(index + 1). \(option.lastPathComponent)")
        }
        let raw = try prompt("Choose comma-separated overlays or leave empty", defaultValue: "", allowEmpty: true)
        guard !raw.isEmpty else {
            return []
        }

        let indices = raw
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 >= 1 && $0 <= options.count }

        return Array(Set(indices)).sorted().map { options[$0 - 1] }
    }

    static func printError(_ message: String) {
        fputs(message + "\n", stderr)
    }
}
