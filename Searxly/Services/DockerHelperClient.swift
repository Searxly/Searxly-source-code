//
//  DockerHelperClient.swift
//  Searxly
//
//  Manages the NSXPCConnection to the SearxlyDockerHelper XPC service.
//  LocalSearxngManager calls through this instead of spawning docker processes directly.
//

import Foundation

/// Thin wrapper around NSXPCConnection to SearxlyDockerHelper.
/// Lazy-connects on first use and auto-reconnects after invalidation or interruption.
///
/// Must be used from the @MainActor (same isolation as LocalSearxngManager).
@MainActor
final class DockerHelperClient {
    static let shared = DockerHelperClient()
    private init() {}

    private var connection: NSXPCConnection?

    /// Returns a ready-to-use proxy, creating (or recreating) the connection as needed.
    ///
    /// The proxy is vended with a per-message error handler: if the XPC service can't be
    /// reached (failed to launch, crashed mid-call), the handler drops the stale connection
    /// so the *next* call rebuilds a fresh one instead of reusing a dead proxy.
    func proxy() -> SearxlyDockerHelperProtocol? {
        if connection == nil {
            let c = NSXPCConnection(serviceName: "com.myrhex.SearxlyDockerHelper")
            c.remoteObjectInterface = NSXPCInterface(with: SearxlyDockerHelperProtocol.self)
            c.invalidationHandler = { [weak self] in
                Task { @MainActor [weak self] in self?.connection = nil }
            }
            c.interruptionHandler = { [weak self] in
                Task { @MainActor [weak self] in self?.connection = nil }
            }
            c.resume()
            connection = c
        }
        let errorHandler: (Error) -> Void = { [weak self] error in
            print("DockerHelperClient: XPC message failed — \(error.localizedDescription)")
            Task { @MainActor [weak self] in self?.connection = nil }
        }
        return connection?.remoteObjectProxyWithErrorHandler(errorHandler) as? SearxlyDockerHelperProtocol
    }

    /// Tears down the connection immediately (call on app termination or if the XPC service crashes unrecoverably).
    func invalidate() {
        connection?.invalidate()
        connection = nil
    }
}
