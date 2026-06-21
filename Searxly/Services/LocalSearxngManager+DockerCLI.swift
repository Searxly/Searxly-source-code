//
//  LocalSearxngManager+DockerCLI
//  Searxly
//

import Foundation
import SwiftUI
import Observation
import Security

extension LocalSearxngManager {
    // MARK: - Docker Discovery (macOS friendly)

    /// Attempts to find a usable `docker` binary on macOS.
    /// Docker Desktop does not always put `docker` in the PATH visible to apps.
    func locateDocker() -> String? {
        if let cached = cachedDockerPath {
            return cached
        }

        // Common locations on macOS (Docker Desktop, Homebrew, OrbStack, Colima, etc.)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",                    // Apple Silicon Homebrew
            "/usr/bin/docker",
            // Docker Desktop CLI socket / helper path (after enabling in Settings > General)
            home.appendingPathComponent("Library/Containers/com.docker.docker/Data/docker-cli").path,
            // OrbStack (popular lightweight alternative)
            home.appendingPathComponent(".orbstack/bin/docker").path,
            // Colima (common with Lima)
            home.appendingPathComponent(".colima/bin/docker").path,
            "/opt/colima/bin/docker"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedDockerPath = path
                return path
            }
        }

        // Last resort: try resolving via the shell (works better from Terminal than from app)
        if let resolved = resolveDockerViaWhich() {
            cachedDockerPath = resolved
            return resolved
        }

        return nil
    }

    /// Locates the docker-credential-desktop helper (or similar) that Docker Desktop uses for credential storage.
    /// This is often missing from PATH when spawning docker from a sandboxed app or non-login shell.
    /// We explicitly find it and ensure its directory is in the subprocess PATH.
    func locateDockerCredentialHelper() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser

        let candidates = [
            "/usr/local/bin/docker-credential-desktop",
            "/opt/homebrew/bin/docker-credential-desktop",
            home.appendingPathComponent(".docker/bin/docker-credential-desktop").path,
            home.appendingPathComponent("Library/Group Containers/group.com.docker/docker-credential-desktop").path,
            "/Applications/Docker.app/Contents/Resources/bin/docker-credential-desktop",
            // Sometimes installed alongside the main docker we located
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // If we already located the main docker binary, check in the same directory
        if let dockerPath = locateDocker() {
            let dir = (dockerPath as NSString).deletingLastPathComponent
            let helper = (dir as NSString).appendingPathComponent("docker-credential-desktop")
            if FileManager.default.isExecutableFile(atPath: helper) {
                return helper
            }
        }

        return nil
    }

    /// Returns the environment dictionary we should use when spawning any `docker` / `docker compose` process.
    /// This is critical because the Docker CLI inside the app does not always inherit the user's shell
    /// environment, and the daemon socket location has moved in modern Docker Desktop
    /// (~/ .docker/run/docker.sock instead of the old container path).
    ///
    /// We also force a rich PATH so that `docker-credential-desktop` (and other helpers) are found.
    /// This fixes the common "exec: \"docker-credential-desktop\": executable file not found in $PATH" error
    /// when running from the app during automatic container setup.
    func dockerEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["COMPOSE_ANSI"] = "never"
        env["DOCKER_CLI_HINTS"] = "false"

        // Explicitly point at the socket the user is actually seeing in the error logs.
        // This makes `docker ps`, `docker compose`, etc. succeed even when the CLI binary
        // was found via one of the helper paths above.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let modernSocket = home.appendingPathComponent(".docker/run/docker.sock").path
        if FileManager.default.fileExists(atPath: modernSocket) {
            env["DOCKER_HOST"] = "unix://" + modernSocket
        } else {
            // Fallback to the classic Docker Desktop raw socket if the new one isn't there yet.
            let classicSocket = home.appendingPathComponent("Library/Containers/com.docker.docker/Data/docker.raw.sock").path
            if FileManager.default.fileExists(atPath: classicSocket) {
                env["DOCKER_HOST"] = "unix://" + classicSocket
            }
        }

        // === Fix for docker-credential-desktop not found in $PATH ===
        // Build a robust PATH for the subprocess. Docker Desktop's credential helper
        // (docker-credential-desktop) is frequently not discoverable from sandboxed apps
        // or when the normal user shell PATH is not inherited.
        var pathComponents: [String] = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]

        // Add the directory of the main docker binary we located (highest priority)
        if let dockerPath = locateDocker() {
            let dockerDir = (dockerPath as NSString).deletingLastPathComponent
            if !pathComponents.contains(dockerDir) {
                pathComponents.insert(dockerDir, at: 0)
            }
        }

        // Explicitly locate and prioritize the credential helper directory
        if let helperPath = locateDockerCredentialHelper() {
            let helperDir = (helperPath as NSString).deletingLastPathComponent
            if !pathComponents.contains(helperDir) {
                pathComponents.insert(helperDir, at: 0)
            }
        }

        // Common Docker Desktop helper locations (Group Containers, app bundle, etc.)
        let extraDockerDirs = [
            home.appendingPathComponent("Library/Group Containers/group.com.docker").path,
            "/Applications/Docker.app/Contents/Resources/bin",
            home.appendingPathComponent(".docker/bin").path,
        ]
        for dir in extraDockerDirs {
            if !pathComponents.contains(dir) && FileManager.default.fileExists(atPath: dir) {
                pathComponents.insert(dir, at: 0)
            }
        }

        let currentPath = env["PATH"] ?? ""
        env["PATH"] = pathComponents.joined(separator: ":") + (currentPath.isEmpty ? "" : ":" + currentPath)

        // Help Docker find its config (where credsStore: "desktop" is usually set)
        if env["DOCKER_CONFIG"] == nil {
            let dockerConfig = home.appendingPathComponent(".docker").path
            if FileManager.default.fileExists(atPath: dockerConfig) {
                env["DOCKER_CONFIG"] = dockerConfig
            }
        }

        return env
    }

    func resolveDockerViaWhich() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["docker"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty,
                   FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {
            // Silently ignore
        }
        return nil
    }

    // MARK: - Private Helpers

    func isDockerDaemonReachable() async -> Bool {
        await withCheckedContinuation { continuation in
            guard let proxy = DockerHelperClient.shared.proxy() else {
                continuation.resume(returning: false)
                return
            }
            proxy.isDaemonReachable { reachable in
                continuation.resume(returning: reachable)
            }
        }
    }

    func checkDockerAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            guard let proxy = DockerHelperClient.shared.proxy() else {
                continuation.resume(returning: false)
                return
            }
            proxy.checkDockerAvailable { available in
                continuation.resume(returning: available)
            }
        }
    }

    func checkIfContainerIsRunning() async -> Bool {
        await withCheckedContinuation { continuation in
            guard let proxy = DockerHelperClient.shared.proxy() else {
                continuation.resume(returning: false)
                return
            }
            proxy.isContainerRunning { running in
                continuation.resume(returning: running)
            }
        }
    }

    /// Additional probe: does the SearXNG web server actually respond?
    /// This catches the case where `docker ps` says the container is running but the Python app
    /// inside is still booting (very common on first start or slower Macs). Searches will fail
    /// until this returns true.
    func isLocalWebReady() async -> Bool {
        for base in localWebProbeURLs {
            guard let url = URL(string: base) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "HEAD"
            req.timeoutInterval = 4.0   // more forgiving during slow first boot / Python startup inside the container
            // HEAD request — we only care whether the server answers at all (lighter than GET / full page).
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse {
                    // Any response in 2xx-5xx range means the HTTP server is up and listening.
                    if (200...599).contains(http.statusCode) {
                        return true
                    }
                }
            } catch {
                // timeout, refused, TLS error, etc. → not ready yet
                continue
            }
        }
        return false
    }

    /// Patches the on-disk docker-compose.yml to respect the current bindToLocalhostOnly setting.
    /// 
    /// SECURITY MODEL:
    /// - "Bind only to localhost" is achieved by prefixing the *host* side of the published port
    ///   (127.0.0.1:8080:8080 vs 8080:8080). This prevents other machines on the LAN from reaching it.
    /// - Inside the container the app **must** listen on 0.0.0.0 (all interfaces). If it binds only
    ///   to the container's 127.0.0.1, Docker's port forwarding (which arrives on the container's
    ///   main veth interface) will not be accepted by the server → host HTTP checks fail even though
    ///   the container is running.
    ///
    /// We therefore:
    /// - Always patch the ports publish prefix according to the toggle.
    /// - Force SEARXNG_BIND_ADDRESS=0.0.0.0 inside the container (the toggle does not affect inside bind).
    /// - Also pass the variables via the compose process environment as a belt-and-suspenders.
}
