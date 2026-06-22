//
//  Log.swift
//  Searxly
//

import Foundation
import os

// Categorized logging via os.Logger. Interpolated values are redacted by default in release; mark
// non-sensitive values `.public` explicitly when they need to be readable.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.myrhex.Searxly"

    static let security = Logger(subsystem: subsystem, category: "security")
    static let privacy = Logger(subsystem: subsystem, category: "privacy")
    static let wallet = Logger(subsystem: subsystem, category: "wallet")
    static let ai = Logger(subsystem: subsystem, category: "ai")
    static let search = Logger(subsystem: subsystem, category: "search")
    static let web = Logger(subsystem: subsystem, category: "web")
    static let adblock = Logger(subsystem: subsystem, category: "adblock")
    static let docker = Logger(subsystem: subsystem, category: "docker")
    static let app = Logger(subsystem: subsystem, category: "general")
}
