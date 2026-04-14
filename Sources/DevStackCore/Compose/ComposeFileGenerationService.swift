import Foundation

enum ComposeFileGenerationService {
    static func generatedComposeFile(
        profile: ProfileDefinition,
        store: ProfileStore,
        server: RemoteServerDefinition?
    ) throws -> (composeURL: URL, plan: ComposePlan) {
        let plan = try ComposePlanBuilder.plan(profile: profile, store: store)
        try store.ensureRuntimeDirectories()
        let generatedDirectory = store.generatedProfileDirectory(for: profile.name)
        try FileManager.default.createDirectory(at: generatedDirectory, withIntermediateDirectories: true)

        guard var normalizedObject = try JSONSerialization.jsonObject(with: plan.normalizedData) as? [String: Any] else {
            throw ValidationError("Failed to rebuild normalized compose model.")
        }
        if let server, !server.isLocal {
            ComposePlanBuilder.rewriteRemoteBindMounts(
                in: &normalizedObject,
                plan: plan,
                server: server,
                profileName: profile.name
            )
        }

        let data = try renderedComposeYAML(from: normalizedObject)
        let composeURL = store.composeFileURL(for: profile.name)
        try data.write(to: composeURL, options: .atomic)
        return (composeURL, plan)
    }

    static func renderedComposeYAML(from normalizedObject: [String: Any]) throws -> Data {
        let lines = yamlLines(for: normalizedObject, indent: 0)
        let text = lines.joined(separator: "\n") + "\n"
        guard let data = text.data(using: .utf8) else {
            throw ValidationError("Failed to encode generated compose YAML.")
        }
        return data
    }

    private static func yamlLines(for value: Any, indent: Int) -> [String] {
        let prefix = String(repeating: " ", count: indent)

        if let object = value as? [String: Any] {
            if object.isEmpty {
                return ["\(prefix){}"]
            }

            var lines: [String] = []
            for key in object.keys.sorted() {
                let renderedKey = yamlKey(key)
                guard let nestedValue = object[key] else {
                    lines.append("\(prefix)\(renderedKey): null")
                    continue
                }

                if let inlineValue = yamlInlineValue(for: nestedValue) {
                    lines.append("\(prefix)\(renderedKey): \(inlineValue)")
                    continue
                }

                if let stringValue = nestedValue as? String, stringValue.contains("\n") {
                    lines.append("\(prefix)\(renderedKey): |-")
                    lines.append(contentsOf: yamlMultilineStringLines(stringValue, indent: indent + 2))
                    continue
                }

                lines.append("\(prefix)\(renderedKey):")
                lines.append(contentsOf: yamlLines(for: nestedValue, indent: indent + 2))
            }
            return lines
        }

        if let array = value as? [Any] {
            if array.isEmpty {
                return ["\(prefix)[]"]
            }

            var lines: [String] = []
            for item in array {
                if let inlineValue = yamlInlineValue(for: item) {
                    lines.append("\(prefix)- \(inlineValue)")
                    continue
                }

                if let stringValue = item as? String, stringValue.contains("\n") {
                    lines.append("\(prefix)- |-")
                    lines.append(contentsOf: yamlMultilineStringLines(stringValue, indent: indent + 2))
                    continue
                }

                lines.append("\(prefix)-")
                lines.append(contentsOf: yamlLines(for: item, indent: indent + 2))
            }
            return lines
        }

        return ["\(prefix)\(yamlInlineValue(for: value) ?? "null")"]
    }

    private static func yamlInlineValue(for value: Any) -> String? {
        if value is NSNull {
            return "null"
        }

        if let boolean = value as? Bool {
            return boolean ? "true" : "false"
        }

        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }

        if let string = value as? String {
            if string.contains("\n") {
                return nil
            }
            return yamlQuotedString(string)
        }

        if let object = value as? [String: Any], object.isEmpty {
            return "{}"
        }

        if let array = value as? [Any], array.isEmpty {
            return "[]"
        }

        return nil
    }

    private static func yamlQuotedString(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private static func yamlKey(_ key: String) -> String {
        if key.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil {
            return key
        }
        return yamlQuotedString(key)
    }

    private static func yamlMultilineStringLines(_ value: String, indent: Int) -> [String] {
        let prefix = String(repeating: " ", count: indent)
        return value.split(separator: "\n", omittingEmptySubsequences: false).map { "\(prefix)\($0)" }
    }
}
