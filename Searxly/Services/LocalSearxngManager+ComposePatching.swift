//
//  LocalSearxngManager+ComposePatching
//  Searxly
//

import Foundation
import SwiftUI
import Observation
import Security

extension LocalSearxngManager {
    func ensureDockerComposeHasBindVars() async {
        guard let proxy = DockerHelperClient.shared.proxy() else { return }
        let composePath = projectFolderURL.appendingPathComponent("docker-compose.yml").path
        guard await proxy.fileExistsAsync(atPath: composePath) else { return }

        guard let data = await proxy.readFileAsync(atPath: composePath),
              var content = String(data: data, encoding: .utf8) else { return }

        let original = content

        let hostBind = bindToLocalhostOnly ? "127.0.0.1:" : ""
        let insideBind = "0.0.0.0"

        let portsRegex = try? NSRegularExpression(pattern: #"- ".*8080:8080"#, options: [])
        if let regex = portsRegex {
            let range = NSRange(content.startIndex..., in: content)
            content = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: #"- "\#(hostBind)8080:8080"#)
        }

        let bindRegex = try? NSRegularExpression(pattern: #"SEARXNG_BIND_ADDRESS=[^\s"]*"#, options: [])
        if let regex = bindRegex {
            let range = NSRange(content.startIndex..., in: content)
            content = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: #"SEARXNG_BIND_ADDRESS=\#(insideBind)"#)
        }

        let pinned = SearxngDockerConfig.pinnedImageReference
        let imageRegex = try? NSRegularExpression(pattern: #"image:\s*searxng/searxng:[^\s\n]+"#, options: [])
        if let regex = imageRegex {
            let range = NSRange(content.startIndex..., in: content)
            content = regex.stringByReplacingMatches(
                in: content,
                options: [],
                range: range,
                withTemplate: "image: \(pinned)"
            )
        }

        if content != original,
           let newData = content.data(using: .utf8) {
            _ = await proxy.writeFileAsync(data: newData, toPath: composePath)
        }

        await ensureSettingsYmlBindsBroadly()
        await ensurePluginsSectionCompatibleIfNeeded()
        await ensureLimiterTomlCompatibleIfNeeded()
    }

    func ensureSettingsYmlBindsBroadly() async {
        guard let proxy = DockerHelperClient.shared.proxy() else { return }
        let settingsPath = projectFolderURL.appendingPathComponent("searxng/settings.yml").path
        guard await proxy.fileExistsAsync(atPath: settingsPath),
              let data = await proxy.readFileAsync(atPath: settingsPath),
              var content = String(data: data, encoding: .utf8) else { return }

        let original = content

        let serverBindRegex = try? NSRegularExpression(
            pattern: #"(bind_address:\s*)["']?[^"'\n]*["']?"#,
            options: []
        )
        if let regex = serverBindRegex {
            let range = NSRange(content.startIndex..., in: content)
            content = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "$1\"0.0.0.0\"")
        }

        let portRegex = try? NSRegularExpression(pattern: #"port:\s*\d+"#, options: [])
        if let regex = portRegex {
            let range = NSRange(content.startIndex..., in: content)
            content = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "port: 8080")
        }

        guard content != original, let newData = content.data(using: .utf8) else { return }
        _ = await proxy.writeFileAsync(data: newData, toPath: settingsPath)
    }

    func sanitizeDockerComposeLine(_ raw: String) -> String {
        let stripped = raw.replacingOccurrences(
            of: #"\u{1B}(?:\[[0-9;?]*[ -/]*[@-~]|\][^\u{7}]*\u{7})"#,
            with: "",
            options: .regularExpression
        )
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func appendSanitizedDockerComposeLogLine(_ raw: String, prefix: String) {
        let line = sanitizeDockerComposeLine(raw)
        guard !line.isEmpty else { return }

        if line.contains("What's next:") { return }
        if line.contains("docker-desktop://") { return }
        if line.contains("Filter, search, and stream logs") { return }
        if line.range(of: #"^\[\+\] up \d+/\d+$"#, options: .regularExpression) != nil { return }
        if line.contains("Container searxng") && line.localizedCaseInsensitiveContains("waiting") { return }
        if line.contains("✔") && line.localizedCaseInsensitiveContains("healthy") {
            logs.append("✅ SearXNG container healthy")
            return
        }

        logs.append(prefix + line)
    }

    func runDockerComposeCommand(_ args: [String]) async {
        guard let proxy = DockerHelperClient.shared.proxy() else {
            lastError = "Docker helper service unavailable."
            status = .error(lastError!)
            logs.append("❌ " + lastError!)
            return
        }

        // Patch the on-disk compose to reflect the current localhost-only preference.
        await ensureDockerComposeHasBindVars()

        let hostBindPrefix = bindToLocalhostOnly ? "127.0.0.1:" : ""
        let extraEnv: [String: String] = [
            "SEARXNG_HOST_BIND": hostBindPrefix,
            "SEARXNG_BIND_ADDRESS": "0.0.0.0",
        ]
        let projectPath = projectFolderURL.path

        let (exitCode, outStr, errStr) = await withCheckedContinuation {
            (continuation: CheckedContinuation<(Int32, String, String), Never>) in
            proxy.runDockerCompose(args: args, projectPath: projectPath, extraEnv: extraEnv) { code, out, err in
                continuation.resume(returning: (code, out, err))
            }
        }

        if exitCode == -1 {
            lastError = errStr.isEmpty ? "Docker CLI not found." : errStr
            status = .error(lastError!)
            logs.append("❌ " + lastError!)
            return
        }

        if !outStr.isEmpty {
            for line in outStr.split(separator: "\n") {
                appendSanitizedDockerComposeLogLine(String(line), prefix: "📄 ")
            }
        }
        if !errStr.isEmpty {
            for line in errStr.split(separator: "\n") {
                let lineStr = sanitizeDockerComposeLine(String(line))
                guard !lineStr.isEmpty else { continue }
                if lineStr.contains("Cannot connect to the Docker daemon") ||
                   lineStr.contains("failed to connect to the docker API") ||
                   lineStr.contains("docker.sock") {
                    lastError = "Docker daemon is not running or the socket is missing."
                    logs.append("❌ " + lastError!)
                    logs.append("💡 " + dockerDaemonHint())
                } else {
                    appendSanitizedDockerComposeLogLine(lineStr, prefix: "⚠️ ")
                }
            }
        }

        if exitCode != 0 {
            if lastError == nil {
                if errStr.contains("does not allow user interaction") || errStr.contains("keychain") {
                    lastError = "Docker image download failed (macOS keychain access). Quit and reopen Searxly, ensure Docker Desktop is running, then tap Start local search again. If this persists, run in Terminal: cd ~/searxng-local && docker compose pull && docker compose up -d"
                    logs.append("❌ " + lastError!)
                    logs.append("   stderr: " + String(errStr.prefix(300)))
                } else if errStr.contains("docker-credential-desktop") || errStr.contains("credential") {
                    lastError = "Docker credential helper not found. This usually means Docker Desktop isn't fully started. Quit Docker Desktop completely (right-click the whale icon in the menu bar → Quit Docker Desktop), reopen it, wait until it says it's running, then tap Recheck."
                    logs.append("❌ " + lastError!)
                    logs.append("   stderr: " + String(errStr.prefix(300)))
                } else {
                    lastError = "docker compose \(args.joined(separator: " ")) failed (exit \(exitCode))"
                    logs.append("❌ " + lastError!)
                    if !errStr.isEmpty {
                        logs.append("   stderr: " + String(errStr.prefix(400)))
                    }
                }
            }
            status = .error(lastError!)
        }
    }

    func ensurePluginsSectionCompatibleIfNeeded() async {
        let migrationKey = "Searxly.DidFixPluginsDictFormat"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        guard let proxy = DockerHelperClient.shared.proxy() else { return }

        let settingsPath = projectFolderURL.appendingPathComponent("searxng/settings.yml").path
        guard await proxy.fileExistsAsync(atPath: settingsPath),
              let data = await proxy.readFileAsync(atPath: settingsPath),
              let content = String(data: data, encoding: .utf8) else { return }

        guard content.contains("\n  searx.plugins.") else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        let startMarker = "\n# Plugin configuration"
        let fallbackStart = "\nplugins:"
        guard let pluginsRange = content.range(of: startMarker) ?? content.range(of: fallbackStart) else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        let afterPlugins = content[pluginsRange.upperBound...]
        let nextSectionMarkers = ["\n# Configuration of", "\nhostnames:", "\nanswerers:", "\ncustom_themes:"]
        var cutPoint = content.endIndex
        for marker in nextSectionMarkers {
            if let r = afterPlugins.range(of: marker) {
                let idx = content.index(pluginsRange.upperBound,
                                        offsetBy: afterPlugins.distance(from: afterPlugins.startIndex, to: r.lowerBound))
                if idx < cutPoint { cutPoint = idx }
            }
        }

        let fixed = String(content[..<pluginsRange.lowerBound]) + "\n" + String(content[cutPoint...])

        if let newData = fixed.data(using: .utf8),
           await proxy.writeFileAsync(data: newData, toPath: settingsPath) {
            logs.append("✅ Removed incompatible plugins: dict section from settings.yml (requires list format in this image). SearXNG will use its built-in plugin defaults.")
            UserDefaults.standard.set(true, forKey: migrationKey)
        } else {
            logs.append("⚠️ Could not remove plugins: dict section (XPC write failed)")
        }
    }

    func ensureLimiterTomlCompatibleIfNeeded() async {
        let migrationKey = "Searxly.DidFixLimiterTomlSchema"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        guard let proxy = DockerHelperClient.shared.proxy() else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        let tomlPath = projectFolderURL.appendingPathComponent("searxng/limiter.toml").path
        guard await proxy.fileExistsAsync(atPath: tomlPath),
              let data = await proxy.readFileAsync(atPath: tomlPath),
              let content = String(data: data, encoding: .utf8) else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        guard content.contains("[botdetection]") && content.contains("ipv4_prefix") else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        let fixed = """
# Permissive limiter config for local private development.
# Works together with server.limiter=false (in settings.yml) and
# SEARXNG_LIMITER=false (docker-compose env).
# Schema must match the pinned image (searxng/searxng:2025.2.12).
# In this version ipv4_prefix/ipv6_prefix live under [real_ip], not [botdetection].

[real_ip]
ipv4_prefix = 32
ipv6_prefix = 48
x_for = 1

[botdetection.ip_limit]
filter_link_local = false
link_token = false

[botdetection.ip_lists]
block_ip = []

pass_ip = [
  '127.0.0.0/8',
  '::1',
  '192.168.0.0/16',
  '10.0.0.0/8',
  '172.16.0.0/12',
  'fe80::/10',
]

pass_searxng_org = false
"""
        if let newData = fixed.data(using: .utf8),
           await proxy.writeFileAsync(data: newData, toPath: tomlPath) {
            logs.append("✅ Fixed limiter.toml schema (moved ipv4_prefix/ipv6_prefix to [real_ip], removed trusted_proxies).")
            UserDefaults.standard.set(true, forKey: migrationKey)
        } else {
            logs.append("⚠️ Could not fix limiter.toml (XPC write failed)")
        }
    }

    func migrateBindToLocalhostOnlyIfNeeded() {
        guard UserDefaults.standard.object(forKey: Self.bindLocalhostOnlyKey) == nil else { return }
        // Under App Sandbox the compose file is unreadable from the main app — default to true (secure).
        // After the first run this key is persisted and the migration never re-runs.
        let inferred: Bool
        let composeURL = projectFolderURL.appendingPathComponent("docker-compose.yml")
        if let content = try? String(contentsOf: composeURL, encoding: .utf8) {
            inferred = content.contains("127.0.0.1:8080")
        } else {
            inferred = true
        }
        UserDefaults.standard.set(inferred, forKey: Self.bindLocalhostOnlyKey)
    }

}
