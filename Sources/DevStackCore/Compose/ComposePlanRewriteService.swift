import Foundation

enum ComposePlanRewriteService {
    static func rewriteRemoteBindMounts(
        in normalizedObject: inout [String: Any],
        plan: ComposePlan,
        server: RemoteServerDefinition,
        profileName: String
    ) {
        guard var servicesObject = normalizedObject["services"] as? [String: Any] else {
            return
        }

        for service in plan.services {
            guard var serviceObject = servicesObject[service.name] as? [String: Any],
                  var volumes = serviceObject["volumes"] as? [[String: Any]]
            else {
                continue
            }

            for index in volumes.indices {
                guard let type = volumes[index]["type"] as? String,
                      type == "bind",
                      let sourcePath = volumes[index]["source"] as? String
                else {
                    continue
                }

                let standardizedSource = standardizedPath(sourcePath)
                guard let relativePath = relativePath(
                    for: standardizedSource,
                    under: standardizedPath(plan.workingDirectory.path)
                ) else {
                    continue
                }

                let remoteSource = server.remoteProfileProjectDirectory(for: profileName)
                    + "/"
                    + relativePath
                volumes[index]["source"] = remoteSource
            }

            serviceObject["volumes"] = volumes
            servicesObject[service.name] = serviceObject
        }

        normalizedObject["services"] = servicesObject
    }

    private static func relativePath(for path: String, under root: String) -> String? {
        guard path == root || path.hasPrefix(root + "/") else {
            return nil
        }

        let suffix = path == root ? "" : String(path.dropFirst(root.count + 1))
        guard !suffix.isEmpty else {
            return nil
        }
        return suffix
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

