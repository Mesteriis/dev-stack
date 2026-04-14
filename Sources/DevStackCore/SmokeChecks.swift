import Foundation

struct SmokeCheckFailure: Error, CustomStringConvertible {
    let description: String
}

package enum DevStackSmokeChecks {
    package static func runAll() throws {
        try testSlugifyReplacesUnsupportedCharacters()
        try testLocalContainerModeMapping()
        try testRemoteServerNormalization()
        try testLegacyModelDecodingDefaults()
        try testCodexRateLimitParser()
        try testTimestampedQuotaIssueParser()
        try testParseComposeServicesImportsPublishedPorts()
        try testParseComposeServicesSupportsLongSyntaxAndHostBindings()
        try testManagedDataRewriteUsesServiceScopedDirectories()
        try testProfileNormalizationGeneratesComposeProjectName()
        try testProfileNormalizationDerivesWorkingDirectoryFromSourceCompose()
        try testProfileNormalizationResolvesComposeOverlays()
        try testManagedVariableNormalizationAndFiltering()
        try testEnvironmentImportParsing()
        try testProfileNormalizationPreservesRuntimeReference()
        try testProfileEncodingUsesRuntimeNameKey()
        try testDXCommandParsing()
        try testProfileImportDraftWiring()
        try testDXUseProfileWiring()
        try testDXEnvCheckFormatting()
        try testUUIDGenerators()
        try testMissingEnvironmentDetection()
        try testClipboardSmartParser()
        try testProfileStoreUsesProjectDataDirectory()
        try testProfileStoreReturnsComposeSourceURLsInOrder()
        try testProfileNormalizationRejectsDuplicateLocalPorts()
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw SmokeCheckFailure(description: message)
        }
    }

    private static func testSlugifyReplacesUnsupportedCharacters() throws {
        try expect(slugify("my service/name") == "my-service-name", "slugify should normalize separators")
        try expect(slugify("   ") == "service", "slugify should fall back for empty values")
    }

    private static func testParseComposeServicesImportsPublishedPorts() throws {
        let compose = """
        services:
          api:
            image: demo/api:latest
            ports:
              - "8080:80"
          redis:
            image: redis:7
            ports:
              - "6379:6379"
        """

        let services = parseComposeServices(from: compose)

        try expect(services.count == 2, "compose parser should return two services")
        try expect(services.map(\.name) == ["api", "redis"], "compose parser should preserve service names")
        try expect(services.map(\.localPort) == [8080, 6379], "compose parser should detect published ports")
        try expect(services.map(\.role) == ["http", "redis"], "compose parser should infer common roles")
    }

    private static func testCodexRateLimitParser() throws {
        let line = """
        {"timestamp":"2026-02-14T13:05:41.155Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":1.0,"window_minutes":300,"resets_at":1771092291}}}}
        """

        let parsed = AIToolQuotaInspector.parseCodexRateLimitEvent(from: line)

        try expect(parsed != nil, "codex rate-limit parser should detect token_count events")
        try expect(parsed?.primaryUsedPercent == 0.01, "codex rate-limit parser should normalize whole-number percent points")
        try expect(parsed?.primaryWindowMinutes == 300, "codex rate-limit parser should read window minutes")
        try expect(parsed?.primaryResetsAt != nil, "codex rate-limit parser should read reset timestamp")
    }

    private static func testTimestampedQuotaIssueParser() throws {
        let line = "2026-04-02T09:14:38.793Z [ERROR] [OPENAI_ERROR] OpenAI API Streaming Error: 429 You exceeded your current quota"
        let parsed = AIToolQuotaInspector.parseTimestampedQuotaIssue(from: line)
        try expect(parsed != nil, "timestamped quota issue parser should decode ISO8601 timestamps")
    }

    private static func testLocalContainerModeMapping() throws {
        try expect(LocalContainerMode(autoDownOnSwitch: false, autoUpOnActivate: false) == .manual, "manual mode should map from disabled flags")
        try expect(LocalContainerMode(autoDownOnSwitch: false, autoUpOnActivate: true) == .startOnActivate, "start-on-activate mode should map from activate flag")
        try expect(LocalContainerMode(autoDownOnSwitch: true, autoUpOnActivate: false) == .stopOnSwitch, "stop-on-switch mode should map from stop flag")
        try expect(LocalContainerMode(autoDownOnSwitch: true, autoUpOnActivate: true) == .switchActive, "switch-active mode should map from both flags")
    }

    private static func testRemoteServerNormalization() throws {
        let sshServer = try RemoteServerDefinition(
            name: "Sandbox Host",
            transport: .ssh,
            dockerContext: "",
            sshHost: "192.168.1.33",
            sshPort: 22,
            sshUser: "root"
        ).normalized()
        try expect(sshServer.dockerContext == "srv-Sandbox-Host", "SSH server should derive a managed docker context name")
        try expect(sshServer.dockerEndpoint == "ssh://root@192.168.1.33", "SSH server should build docker endpoint")
        try expect(
            sshServer.remoteProfileDataDirectory(for: "Demo App") == "/var/lib/devstackmenu/profiles/Demo-App/data",
            "SSH server should derive a remote profile data directory"
        )

        let localServer = try RemoteServerDefinition(
            name: "Local Docker",
            transport: .local,
            dockerContext: "",
            sshHost: "ignored",
            sshPort: 2200,
            sshUser: "ignored"
        ).normalized()
        try expect(localServer.dockerContext == "default", "Local server should fall back to default context")
        try expect(localServer.remoteDockerServerDisplay == "local", "Local server should display local endpoint")
    }

    private static func testLegacyModelDecodingDefaults() throws {
        let legacyServerJSON = """
        {
          "name": "remote",
          "transport": "ssh",
          "dockerContext": "srv-remote",
          "sshHost": "192.168.1.33",
          "sshPort": 22,
          "sshUser": "root"
        }
        """
        let legacyServer = try JSONDecoder().decode(RemoteServerDefinition.self, from: Data(legacyServerJSON.utf8))
        try expect(legacyServer.remoteDataRoot == "/var/lib/devstackmenu", "Legacy server JSON should receive a default remote data root")

        let legacyProfileJSON = """
        {
          "name": "demo",
          "dockerContext": "default",
          "tunnelHost": "docker",
          "shellExports": [],
          "services": [],
          "compose": {
            "projectName": "",
            "workingDirectory": "",
            "autoDownOnSwitch": false,
            "autoUpOnActivate": false,
            "content": ""
          }
        }
        """
        let legacyProfile = try JSONDecoder().decode(ProfileDefinition.self, from: Data(legacyProfileJSON.utf8))
        try expect(legacyProfile.runtimeName.isEmpty, "Legacy profile JSON should decode without a runtime reference")
    }

    private static func testParseComposeServicesSupportsLongSyntaxAndHostBindings() throws {
        let compose = """
        version: "3.9"
        services:
            web:
                image: nginx:latest
                ports:
                    - target: 80
                      published: 8088
                      protocol: tcp
                    - "127.0.0.1:3000:3000"
            worker:
                image: busybox
        """

        let services = parseComposeServices(from: compose)

        try expect(services.count == 2, "compose parser should import both published web ports")
        try expect(services.map(\.name) == ["web-3000", "web-8088"], "compose parser should suffix duplicate service ports")
        try expect(services.map(\.localPort) == [3000, 8088], "compose parser should detect host-bound and long syntax ports")
    }

    private static func testManagedDataRewriteUsesServiceScopedDirectories() throws {
        let compose = """
        services:
          api:
            image: nginx:latest
            volumes:
              - ./data:/usr/share/nginx/html:ro
          worker:
            image: busybox
            volumes:
              - type: bind
                source: ./data/cache
                target: /cache
        """

        let rewrite = RuntimeController.previewManagedDataRewrite(
            content: compose,
            dataRootPath: "/tmp/demo-project/data"
        )

        try expect(
            rewrite.content.contains("/tmp/demo-project/data/api:/usr/share/nginx/html:ro"),
            "short syntax data mounts should become service-scoped"
        )
        try expect(
            rewrite.content.contains("source: /tmp/demo-project/data/worker/cache"),
            "keyed data mounts should become service-scoped"
        )
        try expect(
            rewrite.serviceNames == ["api", "worker"],
            "managed data rewrite should report the affected services"
        )
    }

    private static func testProfileNormalizationGeneratesComposeProjectName() throws {
        let profile = try ProfileDefinition(
            name: "Team Sandbox",
            dockerContext: "default",
            tunnelHost: "docker",
            shellExports: [],
            services: [],
            compose: ComposeDefinition(
                projectName: "",
                workingDirectory: "/tmp/demo",
                autoDownOnSwitch: false,
                autoUpOnActivate: true,
                content: "services:\n  api:\n    image: demo/api"
            )
        ).normalized()

        try expect(profile.compose.projectName == "Team-Sandbox", "normalization should derive compose project name")
    }

    private static func testProfileNormalizationDerivesWorkingDirectoryFromSourceCompose() throws {
        let profile = try ProfileDefinition(
            name: "Tracked Compose",
            dockerContext: "default",
            tunnelHost: "docker",
            shellExports: [],
            services: [],
            compose: ComposeDefinition(
                projectName: "",
                workingDirectory: "/tmp/ignored",
                sourceFile: "/tmp/demo/docker-compose.yml",
                autoDownOnSwitch: false,
                autoUpOnActivate: false,
                content: "services:\n  api:\n    image: demo/api"
            )
        ).normalized()

        try expect(profile.compose.workingDirectory == "/tmp/demo", "source compose should define the project working directory")
    }

    private static func testProfileNormalizationResolvesComposeOverlays() throws {
        let profile = try ProfileDefinition(
            name: "Overlay Demo",
            dockerContext: "default",
            tunnelHost: "docker",
            shellExports: [],
            services: [],
            compose: ComposeDefinition(
                projectName: "",
                sourceFile: "/tmp/demo/docker-compose.yml",
                additionalSourceFiles: ["docker-compose.dev.yml", "/tmp/demo/docker-compose.override.yml"],
                autoDownOnSwitch: false,
                autoUpOnActivate: false,
                content: "services:\n  api:\n    image: demo/api"
            )
        ).normalized()

        try expect(
            profile.compose.additionalSourceFiles == [
                "/tmp/demo/docker-compose.dev.yml",
                "/tmp/demo/docker-compose.override.yml",
            ],
            "relative overlay files should resolve against the main compose file"
        )
    }

    private static func testManagedVariableNormalizationAndFiltering() throws {
        let variable = try ManagedVariableDefinition(
            name: " API_BASE_URL ",
            value: "http://localhost:8080",
            profileNames: ["demo-b", "demo-a", "demo-b"]
        ).normalized()

        try expect(variable.name == "API_BASE_URL", "managed variable should trim the name")
        try expect(variable.profileNames == ["demo-a", "demo-b"], "managed variable should deduplicate and sort profile names")

        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let store = ProfileStore(
            rootDirectory: temporaryRoot,
            logsDirectory: temporaryRoot.appendingPathComponent("logs", isDirectory: true),
            launchAgentsDirectory: temporaryRoot.appendingPathComponent("launch-agents", isDirectory: true)
        )
        try store.saveManagedVariables([
            variable,
            ManagedVariableDefinition(name: "FEATURE_FLAG", value: "1", profileNames: ["demo-b"]),
        ])

        let profile = try ProfileDefinition(name: "demo-a").normalized()
        let applicable = try ComposeSupport.applicableManagedVariables(profile: profile, store: store)
        try expect(applicable.map(\.name) == ["API_BASE_URL"], "variable filtering should return only variables assigned to the profile")
    }

    private static func testEnvironmentImportParsing() throws {
        let parsed = ComposeSupport.parseEnvironmentText(
            """
            # comment
            API_URL=http://localhost:8080
            FEATURE_FLAG=1
            EMPTY=
            """
        )

        try expect(parsed["API_URL"] == "http://localhost:8080", "env parser should keep regular assignments")
        try expect(parsed["FEATURE_FLAG"] == "1", "env parser should keep flag values")
        try expect(parsed["EMPTY"] == "", "env parser should preserve empty assignments")
    }

    private static func testProfileNormalizationPreservesRuntimeReference() throws {
        let profile = try ProfileDefinition(
            name: "Remote Demo",
            serverName: "sandbox-host",
            dockerContext: "srv-sandbox-host",
            tunnelHost: "root@192.168.1.33",
            shellExports: [],
            services: [],
            compose: ComposeDefinition()
        ).normalized()

        try expect(profile.runtimeName == "sandbox-host", "Profile should preserve selected runtime name")
    }

    private static func testProfileEncodingUsesRuntimeNameKey() throws {
        let profile = try ProfileDefinition(
            name: "Remote Demo",
            serverName: "sandbox-host",
            dockerContext: "srv-sandbox-host",
            tunnelHost: "root@192.168.1.33",
            shellExports: [],
            services: [],
            compose: ComposeDefinition()
        ).normalized()

        let data = try JSONEncoder().encode(profile)
        let text = String(decoding: data, as: UTF8.self)
        try expect(text.contains("\"runtimeName\""), "Encoded profile JSON should use runtimeName")
        try expect(!text.contains("\"serverName\""), "Encoded profile JSON should not write legacy serverName")
    }

    private static func testUUIDGenerators() throws {
        let generatedV4 = try ContextValueGenerator.generate(kind: .uuidV4)
        try expect(generatedV4.range(of: #"^[0-9a-f-]{36}$"#, options: .regularExpression) != nil, "UUID v4 generator should emit lowercase UUID text")
        try expect(generatedV4.split(separator: "-")[2].first == "4", "UUID v4 generator should emit version 4 identifiers")

        let fixedDate = Date(timeIntervalSince1970: 1_716_000_000)
        let generatedV7 = try ContextValueGenerator.generate(
            kind: .uuidV7,
            now: fixedDate,
            randomDataProvider: { count in Data(repeating: 0xAB, count: count) }
        )
        try expect(generatedV7.split(separator: "-")[2].first == "7", "UUID v7 generator should emit version 7 identifiers")
        try expect(["8", "9", "a", "b"].contains(String(generatedV7.split(separator: "-")[3].first!)), "UUID v7 generator should emit RFC variant bits")
    }

    private static func testMissingEnvironmentDetection() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(
            rootDirectory: root.appendingPathComponent("state", isDirectory: true),
            logsDirectory: root.appendingPathComponent("logs", isDirectory: true),
            launchAgentsDirectory: root.appendingPathComponent("agents", isDirectory: true)
        )
        try store.ensureRuntimeDirectories()

        let projectDirectory = root.appendingPathComponent("project", isDirectory: true)
        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let composeURL = projectDirectory.appendingPathComponent("docker-compose.yml", isDirectory: false)
        let compose = """
        services:
          app:
            image: demo/app
            environment:
              PRESENT_KEY: ${PRESENT_KEY}
              EMPTY_KEY: ${EMPTY_KEY}
              MANAGED_KEY: ${MANAGED_KEY}
              EXTERNAL_KEY: ${EXTERNAL_KEY}
              MISSING_KEY: ${MISSING_KEY}
        """
        try compose.write(to: composeURL, atomically: true, encoding: .utf8)
        try "PRESENT_KEY=alpha\nEMPTY_KEY=\n".write(
            to: projectDirectory.appendingPathComponent(".env", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let profile = try ProfileDefinition(
            name: "Env Demo",
            serverName: "",
            dockerContext: "default",
            tunnelHost: "docker",
            shellExports: [],
            externalEnvironmentKeys: ["EXTERNAL_KEY"],
            services: [],
            compose: ComposeDefinition(
                projectName: "env-demo",
                workingDirectory: projectDirectory.path,
                sourceFile: composeURL.path,
                additionalSourceFiles: [],
                autoDownOnSwitch: false,
                autoUpOnActivate: false,
                content: compose
            )
        ).normalized()

        try store.upsertManagedVariable(
            try ManagedVariableDefinition(name: "MANAGED_KEY", value: "managed", profileNames: [profile.name]).normalized()
        )

        let overview = try ComposeSupport.environmentOverview(profile: profile, store: store)
        let entries = Dictionary(uniqueKeysWithValues: overview.entries.map { ($0.key, $0) })

        try expect(entries["PRESENT_KEY"]?.isMissing == false, "present env keys should not be reported missing")
        try expect(entries["EMPTY_KEY"]?.isEmptyValue == true, "empty env keys should be detected")
        try expect(entries["MANAGED_KEY"]?.providedByManagedVariables == true, "managed variables should satisfy compose refs")
        try expect(entries["EXTERNAL_KEY"]?.isMarkedExternal == true, "external compose refs should be tracked")
        try expect(entries["MISSING_KEY"]?.isMissing == true, "missing compose refs should be reported")
    }

    private static func testClipboardSmartParser() throws {
        let timestamp = ClipboardSmartParser.parse("1716000000")
        try expect(timestamp?.value?.contains("T") == true, "clipboard parser should convert unix timestamps to ISO dates")

        let json = ClipboardSmartParser.parse("{\"b\":1,\"a\":2}")
        try expect(json?.preview.contains("\"a\"") == true, "clipboard parser should pretty-print JSON")

        let base64 = ClipboardSmartParser.parse("SGVsbG8gRGV2U3RhY2s=")
        try expect(base64?.value == "Hello DevStack", "clipboard parser should decode base64 text")
    }

    private static func testDXCommandParsing() throws {
        let addProfile = try DXCommandParser.parse(["add", "profile", "-f", "docker-compose.yml"])
        try expect(
            addProfile == .addProfile(file: "docker-compose.yml"),
            "dx parser should detect add profile command"
        )
        let useProfile = try DXCommandParser.parse(["use", "profile", "demo"])
        try expect(
            useProfile == .useProfile(name: "demo"),
            "dx parser should detect use profile command"
        )
        let envCheck = try DXCommandParser.parse(["env", "check", "--profile", "demo"])
        try expect(
            envCheck == .envCheck(profile: "demo"),
            "dx parser should detect env check command"
        )
    }

    private static func testProfileImportDraftWiring() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(
            rootDirectory: root.appendingPathComponent("state", isDirectory: true),
            logsDirectory: root.appendingPathComponent("logs", isDirectory: true),
            launchAgentsDirectory: root.appendingPathComponent("agents", isDirectory: true)
        )
        try store.ensureRuntimeDirectories()

        let composeURL = root.appendingPathComponent("docker-compose.yml", isDirectory: false)
        try """
        services:
          api:
            image: nginx
            ports:
              - "8080:80"
        """.write(to: composeURL, atomically: true, encoding: .utf8)

        let runtime = try RemoteServerDefinition(name: "local", transport: .local, dockerContext: "default").normalized()
        let request = ComposeImportRequest(
            composeURL: composeURL,
            composeOverlayURLs: [root.appendingPathComponent("docker-compose.override.yml", isDirectory: false)],
            targetProfileName: "api-dev",
            replaceServices: true,
            services: [ServiceDefinition(name: "api", role: "http", aliasHost: "api.localhost", localPort: 8080, remoteHost: "127.0.0.1", remotePort: 8080, tunnelHost: "", enabled: true, envPrefix: "API", extraExports: [])],
            composeContent: try String(contentsOf: composeURL, encoding: .utf8),
            composeWorkingDirectory: root.path,
            composeProjectName: "demo"
        )

        let draft = try ProfileImportService.draftProfile(
            from: request,
            store: store,
            currentProfileName: nil,
            activeDockerContext: "default",
            dockerContexts: [DockerContextEntry(name: "default", endpoint: "unix:///var/run/docker.sock", isCurrent: true)],
            runtimeTargets: [runtime]
        )

        try expect(draft.runtimeName == "local", "import draft should attach selected runtime")
        try expect(draft.compose.sourceFile == composeURL.path, "import draft should preserve compose source")
        try expect(draft.compose.additionalSourceFiles.count == 1, "import draft should keep overlay files")
        try expect(draft.services.count == 1, "import draft should carry imported services")
    }

    private static func testDXUseProfileWiring() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(
            rootDirectory: root.appendingPathComponent("state", isDirectory: true),
            logsDirectory: root.appendingPathComponent("logs", isDirectory: true),
            launchAgentsDirectory: root.appendingPathComponent("agents", isDirectory: true)
        )
        try store.ensureRuntimeDirectories()
        try store.saveProfile(
            try ProfileDefinition(name: "demo", serverName: "", dockerContext: "default", tunnelHost: "docker").normalized(),
            originalName: nil
        )

        let report = try DXWorkflowService.useProfile(
            named: "demo",
            store: store,
            activate: { name, store in
                try store.saveCurrentProfile(name)
                try store.markProfileActive(name)
            },
            snapshotProvider: { _, profileName in
                AppSnapshot(
                    profile: profileName,
                    configuredDockerContext: "default",
                    activeDockerContext: "default",
                    tunnelLoaded: true,
                    tunnelLabel: "local.devstackmenu.demo",
                    compose: ComposeRuntimeSnapshot(
                        configured: false,
                        projectName: "",
                        workingDirectory: "",
                        autoDownOnSwitch: false,
                        autoUpOnActivate: false,
                        runningServices: []
                    ),
                    services: []
                )
            }
        )

        try expect(store.currentProfileName() == "demo", "dx use profile should update current profile")
        try expect(report.activeProfileName == "demo", "dx use profile should report the selected profile")
    }

    private static func testDXEnvCheckFormatting() throws {
        let overview = ComposeEnvironmentOverview(
            workingDirectory: URL(fileURLWithPath: "/tmp/demo", isDirectory: true),
            profileEnvironmentFile: URL(fileURLWithPath: "/tmp/demo/.env.devstack", isDirectory: false),
            environmentFiles: [],
            referencedKeys: ["API_KEY", "EXTERNAL_TOKEN"],
            entries: [
                ComposeEnvironmentEntry(
                    key: "API_KEY",
                    statusText: "Missing",
                    envFileURL: nil,
                    envFileValue: nil,
                    suggestedWriteURL: URL(fileURLWithPath: "/tmp/demo/.env.devstack", isDirectory: false),
                    providedByManagedVariables: false,
                    hasProfileKeychainValue: false,
                    hasProjectKeychainValue: false,
                    isMarkedExternal: false,
                    isMissing: true,
                    isEmptyValue: false
                ),
                ComposeEnvironmentEntry(
                    key: "EXTERNAL_TOKEN",
                    statusText: "Marked as external",
                    envFileURL: nil,
                    envFileValue: nil,
                    suggestedWriteURL: URL(fileURLWithPath: "/tmp/demo/.env.devstack", isDirectory: false),
                    providedByManagedVariables: false,
                    hasProfileKeychainValue: false,
                    hasProjectKeychainValue: false,
                    isMarkedExternal: true,
                    isMissing: false,
                    isEmptyValue: false
                ),
            ],
            profileServiceName: "devstackmenu.demo",
            projectServiceName: "devstackmenu.demo"
        )

        let text = DXWorkflowService.formatEnvironmentCheck(profileName: "demo", overview: overview)
        try expect(text.contains("API_KEY"), "env check formatter should include missing keys")
        try expect(text.contains("EXTERNAL_TOKEN"), "env check formatter should include external keys")
        try expect(text.contains("Unresolved: 1"), "env check formatter should report unresolved count")
    }

    private static func testProfileStoreUsesProjectDataDirectory() throws {
        let store = ProfileStore()
        let profile = try ProfileDefinition(
            name: "Project Data",
            dockerContext: "default",
            tunnelHost: "docker",
            shellExports: [],
            services: [],
            compose: ComposeDefinition(
                projectName: "",
                workingDirectory: "/tmp/demo-app",
                sourceFile: "/tmp/demo-app/docker-compose.yml",
                autoDownOnSwitch: false,
                autoUpOnActivate: false,
                content: "services:\n  api:\n    image: demo/api"
            )
        ).normalized()

        try expect(
            store.profileDataDirectory(for: profile).path == "/tmp/demo-app/data",
            "profile data should live next to the imported compose file"
        )
        try expect(
            store.serviceDataDirectory(for: profile, serviceName: "api").path == "/tmp/demo-app/data/api",
            "service data should be grouped under the project data directory"
        )
    }

    private static func testProfileStoreReturnsComposeSourceURLsInOrder() throws {
        let store = ProfileStore()
        let profile = try ProfileDefinition(
            name: "Ordered Sources",
            dockerContext: "default",
            tunnelHost: "docker",
            shellExports: [],
            services: [],
            compose: ComposeDefinition(
                sourceFile: "/tmp/demo/docker-compose.yml",
                additionalSourceFiles: [
                    "/tmp/demo/docker-compose.dev.yml",
                    "/tmp/demo/docker-compose.override.yml",
                ],
                content: "services:\n  api:\n    image: demo/api"
            )
        ).normalized()

        try expect(
            store.sourceComposeURLs(for: profile).map(\.path) == [
                "/tmp/demo/docker-compose.yml",
                "/tmp/demo/docker-compose.dev.yml",
                "/tmp/demo/docker-compose.override.yml",
            ],
            "profile store should keep compose source order for multi-file compose"
        )
    }

    private static func testProfileNormalizationRejectsDuplicateLocalPorts() throws {
        let profile = ProfileDefinition(
            name: "demo",
            dockerContext: "default",
            tunnelHost: "docker",
            shellExports: [],
            services: [
                ServiceDefinition(name: "api", localPort: 8080, remotePort: 80),
                ServiceDefinition(name: "web", localPort: 8080, remotePort: 80),
            ],
            compose: ComposeDefinition()
        )

        do {
            _ = try profile.normalized()
            throw SmokeCheckFailure(description: "normalization should reject duplicate ports")
        } catch is ValidationError {
            return
        }
    }
}
