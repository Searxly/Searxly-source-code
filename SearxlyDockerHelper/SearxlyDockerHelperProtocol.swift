//
//  SearxlyDockerHelperProtocol.swift
//  Shared — add to BOTH Searxly and SearxlyDockerHelper targets in Xcode.
//
//  Defines the XPC interface between the Searxly main app and the
//  SearxlyDockerHelper XPC service. All Docker CLI invocations and file-system
//  operations on ~/searxng-local route through this interface so that Phase 2
//  (enabling App Sandbox on the main target) only requires flipping one flag.
//

import Foundation

/// XPC interface between Searxly (main) and SearxlyDockerHelper (XPC service, no sandbox).
///
/// Rules for adding methods:
///   - Use only NSXPCConnection-safe scalar types: String, Bool, Data, Int32.
///   - Collections ([String], [String:String]) must NOT appear as @objc parameters —
///     NSXPCConnection silently drops messages with unregistered collection element classes,
///     and there is no safe Swift API to register AnyClass in Set<AnyHashable>.
///   - Instead, pass collections as JSON-encoded Data (NSData is always whitelisted by XPC).
///   - Every method must have exactly one reply block as its last parameter.
///   - The reply block is called exactly once, even on error paths.
@objc protocol SearxlyDockerHelperProtocol {

    // MARK: - Docker CLI discovery

    /// Locates the `docker` binary on the system.
    /// Returns the full path, or nil if not found in any known location.
    func locateDocker(reply: @escaping (String?) -> Void)

    /// Runs `docker --version`. Returns true if the CLI is accessible.
    func checkDockerAvailable(reply: @escaping (Bool) -> Void)

    /// Runs `docker info`. Returns true if the Docker daemon socket is reachable.
    func isDaemonReachable(reply: @escaping (Bool) -> Void)

    /// Runs `docker ps --filter name=searxng`. Returns true if the container is running.
    func isContainerRunning(reply: @escaping (Bool) -> Void)

    // MARK: - Docker Compose

    /// Runs `docker compose <args>` in `projectPath`.
    ///
    /// `argsJSON` and `extraEnvJSON` are JSON-encoded `[String]` and `[String:String]`
    /// respectively. Using Data avoids NSXPCConnection's collection class-registration
    /// requirement — NSData is always on the XPC whitelist without needing setClasses().
    ///
    /// Reply: (exitCode, stdout, stderr)
    ///   - exitCode == -1 signals an XPC-level error (docker not found, process launch failure).
    ///   - exitCode == 0 means success; non-zero means docker compose itself reported failure.
    func runDockerCompose(
        argsJSON: Data,
        projectPath: String,
        extraEnvJSON: Data,
        reply: @escaping (Int32, String, String) -> Void
    )

    // MARK: - File system (Phase 2: App Sandbox)
    //
    // The sandboxed main app cannot access ~/searxng-local directly.
    // All file I/O on that path routes through these methods.
    // Only String, Bool, Data, Int32 are used — all XPC-safe without class registration.

    /// Returns true if a file or directory exists at path.
    func fileExists(atPath path: String, reply: @escaping (Bool) -> Void)

    /// Reads the file at path. Returns nil if not found or unreadable.
    func readFile(atPath path: String, reply: @escaping (Data?) -> Void)

    /// Atomically writes data to path (creates parent directories as needed).
    /// Returns true on success.
    func writeFile(data: Data, toPath path: String, reply: @escaping (Bool) -> Void)

    /// Creates a directory at path (withIntermediateDirectories: true).
    /// Returns true if the directory now exists (created or already existed).
    func createDirectory(atPath path: String, reply: @escaping (Bool) -> Void)

    /// Removes the item at path (file or directory tree).
    /// Returns true on success or if the item did not exist.
    func removeItem(atPath path: String, reply: @escaping (Bool) -> Void)
}

// MARK: - Convenience wrappers

extension SearxlyDockerHelperProtocol {
    /// Convenience overload that accepts native Swift types and handles JSON encoding.
    func runDockerCompose(
        args: [String],
        projectPath: String,
        extraEnv: [String: String],
        reply: @escaping (Int32, String, String) -> Void
    ) {
        guard let argsData = try? JSONSerialization.data(withJSONObject: args),
              let envData  = try? JSONSerialization.data(withJSONObject: extraEnv) else {
            reply(-1, "", "XPC: JSON encoding of args/extraEnv failed")
            return
        }
        runDockerCompose(argsJSON: argsData, projectPath: projectPath, extraEnvJSON: envData, reply: reply)
    }

    // MARK: Async file-operation wrappers

    func fileExistsAsync(atPath path: String) async -> Bool {
        await withCheckedContinuation { continuation in
            fileExists(atPath: path) { continuation.resume(returning: $0) }
        }
    }

    func readFileAsync(atPath path: String) async -> Data? {
        await withCheckedContinuation { continuation in
            readFile(atPath: path) { continuation.resume(returning: $0) }
        }
    }

    func writeFileAsync(data: Data, toPath path: String) async -> Bool {
        await withCheckedContinuation { continuation in
            writeFile(data: data, toPath: path) { continuation.resume(returning: $0) }
        }
    }

    func createDirectoryAsync(atPath path: String) async -> Bool {
        await withCheckedContinuation { continuation in
            createDirectory(atPath: path) { continuation.resume(returning: $0) }
        }
    }

    func removeItemAsync(atPath path: String) async -> Bool {
        await withCheckedContinuation { continuation in
            removeItem(atPath: path) { continuation.resume(returning: $0) }
        }
    }
}
