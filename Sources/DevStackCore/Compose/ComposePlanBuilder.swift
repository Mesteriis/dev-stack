import Foundation

enum ComposePlanBuilder {
    static func plan(profile: ProfileDefinition, store: ProfileStore) throws -> ComposePlan {
        let workingDirectory = composeWorkingDirectory(for: profile, store: store)
        let sourceComposeURLs = try composeSourceURLs(for: profile, store: store)
        let environmentFiles = try ComposeEnvironmentService.resolvedEnvironmentFiles(
            profile: profile,
            store: store,
            workingDirectory: workingDirectory,
            sourceComposeURLs: sourceComposeURLs
        )

        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }

        let result = Shell.run(
            dockerPath,
            arguments: ComposePlanParsingService.composeArguments(
                projectName: composeProjectName(for: profile),
                sourceComposeURLs: sourceComposeURLs,
                workingDirectory: workingDirectory,
                environmentFiles: environmentFiles,
                command: ["config", "--format", "json"]
            ),
            currentDirectoryURL: workingDirectory
        )

        guard result.exitCode == 0 else {
            throw ValidationError(
                nonEmpty(result.stderr)
                    ?? nonEmpty(result.stdout)
                    ?? "docker compose config failed"
            )
        }

        guard let data = result.stdout.data(using: .utf8),
              let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ValidationError("Failed to parse docker compose config output.")
        }

        return ComposePlanParsingService.buildPlan(
            normalizedObject: jsonObject,
            normalizedData: data,
            projectName: composeProjectName(for: profile),
            workingDirectory: workingDirectory,
            sourceComposeURLs: sourceComposeURLs,
            environmentFiles: environmentFiles
        )
    }

    static func importServices(from content: String, workingDirectory: URL?) -> [ServiceDefinition] {
        do {
            let syntheticProfile = try ProfileDefinition(
                name: "compose-import",
                compose: ComposeDefinition(
                    projectName: "compose-import",
                    workingDirectory: workingDirectory?.path ?? FileManager.default.temporaryDirectory.path,
                    content: content
                )
            ).normalized()
            let plan = try plan(profile: syntheticProfile, store: ProfileStore())
            return ComposePlanParsingService.serviceDefinitions(from: plan)
        } catch {
            return ComposeImportFallbackParser.fallbackImportServices(from: content)
        }
    }

    static func rewriteRemoteBindMounts(
        in normalizedObject: inout [String: Any],
        plan: ComposePlan,
        server: RemoteServerDefinition,
        profileName: String
    ) {
        ComposePlanRewriteService.rewriteRemoteBindMounts(
            in: &normalizedObject,
            plan: plan,
            server: server,
            profileName: profileName
        )
    }

    static func composeProjectName(for profile: ProfileDefinition) -> String {
        let trimmed = profile.compose.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? slugify(profile.name) : trimmed
    }

    static func composeWorkingDirectory(for profile: ProfileDefinition, store: ProfileStore) -> URL {
        if let managedDirectory = store.managedProjectDirectory(for: profile) {
            return managedDirectory
        }

        let trimmed = profile.compose.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return store.generatedProfileDirectory(for: profile.name)
        }
        return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath, isDirectory: true)
    }

    static func composeSourceURLs(for profile: ProfileDefinition, store: ProfileStore) throws -> [URL] {
        let sourceURLs = store.sourceComposeURLs(for: profile)
        if !sourceURLs.isEmpty {
            let missingURLs = sourceURLs.filter { !FileManager.default.fileExists(atPath: $0.path) }
            if !missingURLs.isEmpty {
                let message = missingURLs.map(\.path).joined(separator: ", ")
                throw ValidationError("Compose source file is missing: \(message)")
            }
            return sourceURLs
        }

        let sourceURL = store.generatedComposeSourceURL(for: profile.name)
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try profile.compose.content.write(to: sourceURL, atomically: true, encoding: .utf8)
        return [sourceURL]
    }

    static func composeReferenceText(profile: ProfileDefinition, sourceComposeURLs: [URL]) -> String {
        if !sourceComposeURLs.isEmpty {
            let contents = sourceComposeURLs.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            if !contents.isEmpty {
                return contents.joined(separator: "\n\n")
            }
        }
        return profile.compose.content
    }

    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
