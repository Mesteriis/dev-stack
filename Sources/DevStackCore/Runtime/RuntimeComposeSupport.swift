import Foundation

enum RuntimeComposeSupport {
    static func composePS(profile: ProfileDefinition, store: ProfileStore) throws -> [ComposeRuntimeService] {
        guard profile.compose.configured else {
            return []
        }

        let result = runCompose(profile: profile, store: store, subcommand: ["ps", "--format", "json"])
        guard result.exitCode == 0 else {
            let message = nonEmpty(result.stderr) ?? nonEmpty(result.stdout)
            if let message, !message.lowercased().contains("no such service") {
                throw ValidationError(message)
            }
            return []
        }

        let raw = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return []
        }

        let data = Data(raw.utf8)
        if let decoded = try? JSONDecoder().decode([ComposeRuntimeService].self, from: data) {
            return decoded
        }

        if let decoded = try? JSONDecoder().decode(ComposeRuntimeService.self, from: data) {
            return [decoded]
        }

        return raw
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                try? JSONDecoder().decode(ComposeRuntimeService.self, from: Data(String(line).utf8))
            }
    }

    static func runCompose(
        profile: ProfileDefinition,
        store: ProfileStore,
        subcommand: [String]
    ) -> CommandResult {
        guard let dockerPath = ToolPaths.docker else {
            return CommandResult(exitCode: 127, stdout: "", stderr: "docker not found")
        }

        do {
            let server = try RuntimeContextSupport.resolveServerDefinition(for: profile, store: store)
            let resolvedServer = try RuntimeContextSupport.resolvePrimaryServer(for: profile, store: store)
            let generated = try ComposeSupport.generatedComposeFile(profile: profile, store: store, server: server)
            let arguments = [
                "--context",
                resolvedServer.dockerContext,
                "compose",
                "--project-name",
                generated.plan.projectName,
                "--project-directory",
                generated.plan.workingDirectory.path,
                "-f",
                generated.composeURL.path,
            ] + subcommand

            return Shell.run(
                dockerPath,
                arguments: arguments,
                currentDirectoryURL: generated.plan.workingDirectory
            )
        } catch {
            return CommandResult(exitCode: 1, stdout: "", stderr: error.localizedDescription)
        }
    }

    static func composeVolumes(profile: ProfileDefinition, store: ProfileStore) throws -> [ComposeVolumeRecord] {
        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }

        let projectName = ComposePlanBuilder.composeProjectName(for: profile)
        let resolvedServer = try RuntimeContextSupport.resolvePrimaryServer(for: profile, store: store)
        let listResult = Shell.run(
            dockerPath,
            arguments: [
                "--context", resolvedServer.dockerContext,
                "volume", "ls",
                "--filter", "label=com.docker.compose.project=\(projectName)",
                "--format", "{{.Name}}",
            ]
        )
        guard listResult.exitCode == 0 else {
            throw ValidationError(nonEmpty(listResult.stderr) ?? nonEmpty(listResult.stdout) ?? "Failed to list compose volumes")
        }

        let names = listResult.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return try names.map { name in
            let inspect = Shell.run(
                dockerPath,
                arguments: ["--context", resolvedServer.dockerContext, "volume", "inspect", name, "--format", "{{json .}}"]
            )
            guard inspect.exitCode == 0,
                  let data = inspect.stdout.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return ComposeVolumeRecord(name: name, mountpoint: nil, driver: nil)
            }

            return ComposeVolumeRecord(
                name: name,
                mountpoint: object["Mountpoint"] as? String,
                driver: object["Driver"] as? String
            )
        }
    }

    static func composeContainerIDs(profile: ProfileDefinition, store: ProfileStore) throws -> [String] {
        let result = runCompose(profile: profile, store: store, subcommand: ["ps", "-q"])
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "Failed to list compose containers")
        }

        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
