//
//  DockerHelperService.swift
//  SearxlyDockerHelper — XPC Service
//
//  Implements SearxlyDockerHelperProtocol. This process runs without App Sandbox,
//  so it can locate docker, spawn docker CLI subprocesses, and access ~/searxng-local.
//
//  Phase 1: Docker CLI invocations only.
//  Phase 2 (future): file-system operations on ~/searxng-local will be added here
//  once the main target's App Sandbox is enabled.
//

import Foundation

// MARK: - Service implementation

final class DockerHelperService: NSObject, SearxlyDockerHelperProtocol {

    /// Cached path to the keychain-free Docker config directory (see keychainFreeDockerConfigDir).
    private var cachedKeychainFreeConfigDir: String?

    // MARK: Protocol — Docker CLI discovery

    func locateDocker(reply: @escaping (String?) -> Void) {
        reply(findDockerBinary())
    }

    func checkDockerAvailable(reply: @escaping (Bool) -> Void) {
        guard let path = findDockerBinary() else { reply(false); return }
        let env = buildDockerEnv(dockerPath: path)
        reply(runQuiet(path, args: dockerCLIArgs(subcommand: ["--version"]), env: env) == 0)
    }

    func isDaemonReachable(reply: @escaping (Bool) -> Void) {
        guard let path = findDockerBinary() else { reply(false); return }
        let env = buildDockerEnv(dockerPath: path)
        reply(runQuiet(path, args: dockerCLIArgs(subcommand: ["info", "-f", "{{.ServerVersion}}"]), env: env) == 0)
    }

    func isContainerRunning(reply: @escaping (Bool) -> Void) {
        guard let path = findDockerBinary() else { reply(false); return }
        let env = buildDockerEnv(dockerPath: path)
        let (_, out, _) = runCapturing(
            path,
            args: dockerCLIArgs(subcommand: ["ps", "--filter", "name=searxng", "--format", "{{.Names}}"]),
            env: env,
            cwd: nil
        )
        reply(out.contains("searxng"))
    }

    // MARK: Protocol — Docker Compose

    func runDockerCompose(
        argsJSON: Data,
        projectPath: String,
        extraEnvJSON: Data,
        reply: @escaping (Int32, String, String) -> Void
    ) {
        guard let args = (try? JSONSerialization.jsonObject(with: argsJSON)) as? [String],
              let extraEnv = (try? JSONSerialization.jsonObject(with: extraEnvJSON)) as? [String: String]
        else {
            reply(-1, "", "XPC helper: failed to decode args/extraEnv JSON")
            return
        }

        guard let path = findDockerBinary() else {
            reply(-1, "", "Docker CLI not found in any known location.")
            return
        }

        var env = buildDockerEnv(dockerPath: path)
        for (k, v) in extraEnv { env[k] = v }

        let cwd = URL(fileURLWithPath: projectPath)
        let (code, out, err) = runCapturing(
            path,
            args: dockerCLIArgs(subcommand: ["compose"] + args),
            env: env,
            cwd: cwd
        )
        reply(code, out, err)
    }

    // MARK: Protocol — File system

    func fileExists(atPath path: String, reply: @escaping (Bool) -> Void) {
        reply(FileManager.default.fileExists(atPath: path))
    }

    func readFile(atPath path: String, reply: @escaping (Data?) -> Void) {
        reply(FileManager.default.contents(atPath: path))
    }

    func writeFile(data: Data, toPath path: String, reply: @escaping (Bool) -> Void) {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            reply(true)
        } catch {
            reply(false)
        }
    }

    func createDirectory(atPath path: String, reply: @escaping (Bool) -> Void) {
        do {
            try FileManager.default.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: nil
            )
            reply(true)
        } catch {
            reply(FileManager.default.fileExists(atPath: path))
        }
    }

    func removeItem(atPath path: String, reply: @escaping (Bool) -> Void) {
        guard FileManager.default.fileExists(atPath: path) else { reply(true); return }
        do {
            try FileManager.default.removeItem(atPath: path)
            reply(true)
        } catch {
            reply(false)
        }
    }

    // MARK: - Docker binary discovery

    private func findDockerBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [String] = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/bin/docker",
            home.appendingPathComponent("Library/Containers/com.docker.docker/Data/docker-cli").path,
            home.appendingPathComponent(".orbstack/bin/docker").path,
            home.appendingPathComponent(".colima/bin/docker").path,
            "/opt/colima/bin/docker",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return resolveViaWhich()
    }

    private func resolveViaWhich() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["docker"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
            return path
        } catch {
            return nil
        }
    }

    // MARK: - Environment construction

    /// Prepends `docker --config <keychain-free-dir>` to every CLI invocation.
    /// Belt-and-suspenders alongside DOCKER_CONFIG — some Docker Desktop builds still read
    /// credsStore from ~/.docker when only the env var is set.
    private func dockerCLIArgs(subcommand: [String]) -> [String] {
        guard let cfgDir = keychainFreeDockerConfigDir() else { return subcommand }
        return ["--config", cfgDir] + subcommand
    }

    private func buildDockerEnv(dockerPath: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Never inherit the main app's ~/.docker config — it carries credsStore:"desktop"
        // and plugin hooks that force docker-credential-desktop to touch the login keychain.
        // That fails in this XPC service's non-interactive session.
        env.removeValue(forKey: "DOCKER_CONFIG")
        env.removeValue(forKey: "DOCKER_AUTH_CONFIG")

        // Point at the Docker socket (modern path first, then classic fallback).
        let modernSocket = home.appendingPathComponent(".docker/run/docker.sock").path
        let classicSocket = home.appendingPathComponent(
            "Library/Containers/com.docker.docker/Data/docker.raw.sock"
        ).path
        if FileManager.default.fileExists(atPath: modernSocket) {
            env["DOCKER_HOST"] = "unix://" + modernSocket
        } else if FileManager.default.fileExists(atPath: classicSocket) {
            env["DOCKER_HOST"] = "unix://" + classicSocket
        }

        // PATH for docker + compose plugin only — deliberately excludes docker-credential-desktop
        // directories so a mis-set config cannot reach the keychain helper.
        var pathComponents: [String] = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]

        let dockerDir = (dockerPath as NSString).deletingLastPathComponent
        if !pathComponents.contains(dockerDir) {
            pathComponents.insert(dockerDir, at: 0)
        }

        let extraDockerDirs: [String] = [
            "/Applications/Docker.app/Contents/Resources/bin",
            home.appendingPathComponent(".docker/bin").path,
        ]
        for dir in extraDockerDirs
            where !pathComponents.contains(dir) && FileManager.default.fileExists(atPath: dir) {
            pathComponents.insert(dir, at: 0)
        }

        let currentPath = env["PATH"] ?? ""
        env["PATH"] = pathComponents.joined(separator: ":")
            + (currentPath.isEmpty ? "" : ":" + currentPath)

        if let cfgDir = keychainFreeDockerConfigDir() {
            env["DOCKER_CONFIG"] = cfgDir
            env["DOCKER_AUTH_CONFIG"] = "{}"
        }

        // Always suppress ANSI color codes and CLI hints in the helper.
        env["COMPOSE_ANSI"] = "never"
        env["DOCKER_CLI_HINTS"] = "false"

        return env
    }

    /// Builds (and caches on disk) a MINIMAL, self-contained Docker config directory used only for
    /// pulling/running the pinned public SearXNG image from this XPC service.
    ///
    /// It deliberately does NOT copy the user's ~/.docker/config.json. That config carries two things
    /// that break a non-interactive launchd process, both surfacing as the same fatal
    /// "error getting credentials … the current session does not allow user interaction":
    ///   1. `credsStore: "desktop"` → docker-credential-desktop reads the login keychain on every
    ///      registry call (even anonymous public pulls).
    ///   2. Docker Desktop plugin hooks (`features.hooks` + the scout/ai/compose `plugins.*.hooks`),
    ///      which fire on `compose pull`/`up` and authenticate via the same keychain helper.
    /// A public image needs no credentials at all, so we ship a clean config with neither — plus
    /// `cliPluginsExtraDirs` so the `docker compose` plugin is still found once DOCKER_CONFIG moves
    /// away from ~/.docker. The daemon endpoint comes from the explicit DOCKER_HOST set above, so no
    /// `currentContext` is needed.
    private func keychainFreeDockerConfigDir() -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // cliPluginsExtraDirs keeps `docker compose` resolvable under the overridden DOCKER_CONFIG.
        let pluginDirCandidates = [
            home.appendingPathComponent(".docker/cli-plugins").path,
            "/usr/local/lib/docker/cli-plugins",
            "/opt/homebrew/lib/docker/cli-plugins",
            "/Applications/Docker.app/Contents/Resources/cli-plugins",
        ]
        let pluginDirs = pluginDirCandidates.filter {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: $0, isDirectory: &isDir) && isDir.boolValue
        }

        let config: [String: Any] = [
            "auths": [String: String](),
            "cliPluginsExtraDirs": pluginDirs,
            "features": ["hooks": "false"],
            // Explicitly blank out Docker Desktop plugin hooks (scout pull hook is a common culprit).
            "plugins": [
                "scout": ["hooks": ""],
                "ai": ["hooks": ""],
                "compose": ["hooks": ""],
            ],
        ]

        let dirCandidates = [
            home.appendingPathComponent("Library/Application Support/Searxly/docker-config"),
            URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("searxly-docker-config"),
        ]

        for outDir in dirCandidates {
            do {
                try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
                let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted])
                try data.write(to: outDir.appendingPathComponent("config.json"), options: .atomic)
                let path = outDir.path
                cachedKeychainFreeConfigDir = path
                return path
            } catch {
                continue
            }
        }

        return nil
    }

    // MARK: - Process execution

    /// Runs a command and discards output; returns only the exit code.
    @discardableResult
    private func runQuiet(_ executable: String, args: [String], env: [String: String]? = nil) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let env { process.environment = env }
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    /// Runs a command and returns (exitCode, stdout, stderr).
    private func runCapturing(
        _ executable: String,
        args: [String],
        env: [String: String],
        cwd: URL?
    ) -> (Int32, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.environment = env
        if let cwd { process.currentDirectoryURL = cwd }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Drain both pipes concurrently with the process running. Reading only AFTER
        // waitUntilExit() deadlocks when the child fills the ~64KB pipe buffer — exactly
        // what `docker compose pull` (verbose layer-download progress) and `up` do on first
        // run. The child blocks on write while we block on wait, and onboarding hangs forever.
        var outData = Data()
        var errData = Data()
        let ioGroup = DispatchGroup()
        let ioQueue = DispatchQueue(label: "com.myrhex.SearxlyDockerHelper.io", attributes: .concurrent)

        ioGroup.enter()
        ioQueue.async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            ioGroup.leave()
        }
        ioGroup.enter()
        ioQueue.async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            ioGroup.leave()
        }

        do {
            try process.run()
        } catch {
            // Process never launched — close the write ends so the drain tasks see EOF.
            try? outPipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForWriting.close()
            ioGroup.wait()
            return (-1, "", error.localizedDescription)
        }

        process.waitUntilExit()
        ioGroup.wait()   // ensure both pipes are fully drained before decoding

        return (
            process.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
