import Foundation

package func parseDockerContexts(from raw: String) -> [DockerContextEntry] {
    raw
        .split(whereSeparator: \.isNewline)
        .compactMap { line -> DockerContextEntry? in
            let parts = String(line).components(separatedBy: "\t")
            guard parts.count >= 3 else {
                return nil
            }
            return DockerContextEntry(
                name: parts[0],
                endpoint: parts[2],
                isCurrent: parts[1] == "*"
            )
        }
}

package func slugify(_ value: String) -> String {
    let pattern = "[^A-Za-z0-9._-]+"
    let range = value.range(of: pattern, options: .regularExpression) ?? value.startIndex..<value.startIndex
    let replaced = value.replacingOccurrences(of: pattern, with: "-", options: .regularExpression)
    if !range.isEmpty || !replaced.isEmpty {
        return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-")).ifEmpty("service")
    }
    return "service"
}

package func inferRole(serviceName: String, publishedPort: Int) -> String {
    let lowered = serviceName.lowercased()
    if lowered.contains("postgres") || lowered == "db" || publishedPort == 5432 {
        return "postgres"
    }
    if lowered.contains("redis") || publishedPort == 6379 {
        return "redis"
    }
    if lowered.contains("minio") || publishedPort == 9000 {
        return "minio"
    }
    if publishedPort == 443 || lowered.contains("https") {
        return "https"
    }
    if lowered.contains("api") || lowered.contains("web") || lowered.contains("nginx")
        || lowered.contains("frontend") || publishedPort == 80 || publishedPort == 8000 || publishedPort == 8080
    {
        return "http"
    }
    return "generic"
}

package func parseComposeServices(from content: String) -> [ServiceDefinition] {
    ComposeSupport.importServices(from: content, workingDirectory: nil)
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
