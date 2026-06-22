//
//  Log.swift
//  Searxly
//
//  One place for all logging. Replaces raw `print(...)` across the app.
//
//  WHY THIS EXISTS (privacy hygiene): `print` writes everything, verbatim, to stdout, where it can be
//  captured by Console.app / `log stream` and — worse — persisted. For a privacy browser that handles
//  search queries, history, keys, and credentials, that's a leak surface. `os.Logger`:
//    • Redacts interpolated dynamic values as `<private>` in release builds by default (you must opt a
//      value into the log with `\(value, privacy: .public)`), so sensitive data never lands in the log.
//    • `.debug`/`.info` are NOT written to the persistent store (memory-only, dropped under pressure)
//      and are stripped from release builds — so routine chatter leaves no durable plaintext trail.
//    • `.notice`/`.error`/`.fault` persist, so genuine problems are still recoverable from a sysdiagnose.
//    • Categories let you filter:  `log stream --predicate 'subsystem == "com.myrhex.Searxly"'`
//
//  GUIDELINE: log STATIC strings freely. Only interpolate values that are safe to persist, and mark
//  anything that is genuinely public/non-sensitive with `privacy: .public` if you need to see it in a
//  release build. Never interpolate secrets, full URLs of private browsing, queries, or key material.
//

import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.myrhex.Searxly"

    /// Keychain, encryption, App Lock, recovery — the security core.
    static let security = Logger(subsystem: subsystem, category: "security")
    /// Privacy actions: history/bookmark clears, panic wipe, data reset.
    static let privacy = Logger(subsystem: subsystem, category: "privacy")
    /// Self-custody wallet (keys stay device-only; never log secrets here).
    static let wallet = Logger(subsystem: subsystem, category: "wallet")
    /// On-device + cloud AI lifecycle (load/unload, providers, RAG).
    static let ai = Logger(subsystem: subsystem, category: "ai")
    /// SearXNG / search coordination.
    static let search = Logger(subsystem: subsystem, category: "search")
    /// WebKit / navigation / tabs.
    static let web = Logger(subsystem: subsystem, category: "web")
    /// Ad & tracker blocking.
    static let adblock = Logger(subsystem: subsystem, category: "adblock")
    /// Local SearXNG Docker provisioning / lifecycle.
    static let docker = Logger(subsystem: subsystem, category: "docker")
    /// Catch-all for general app events.
    static let app = Logger(subsystem: subsystem, category: "general")
}
