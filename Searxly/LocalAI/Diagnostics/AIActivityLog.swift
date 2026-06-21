//
//  AIActivityLog.swift
//  Searxly
//
//  Moved to Diagnostics/ during 2026 Local AI full reorg (chatbot + user-called actions + organized folders).
//  Lightweight export helpers for the in-memory activity ring (actual state lives in the manager).
//  All text is privacy-safe (no full page bodies, only summaries + counts).
//  Used by settings "Review recent AI actions" and the full diagnostics report.
//

import Foundation
import AppKit   // For NSPasteboard (copy log to clipboard)

enum AIActivityLog {

    /// Export the provided actions as a simple, user-readable audit text.
    /// Safe to call even when encryption is on (we only export what the user explicitly asks for).
    static func exportAsText(_ actions: [AIAction]) -> String {
        var lines: [String] = []
        lines.append("Searxly Local AI Activity Log — \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("All processing happened 100% on this Mac. Nothing was sent to any server.")
        lines.append("Prompt version: \(AIPromptLibrary.promptVersion)")
        lines.append("---")
        for a in actions {
            let ts = ISO8601DateFormatter().string(from: a.timestamp)
            let used = a.usedModel ? " (model used)" : ""
            lines.append("[\(ts)] \(a.type.rawValue)\(used): \(a.summary)")
            if let d = a.detail, !d.isEmpty {
                lines.append("    detail: \(d)")
            }
        }
        lines.append("---")
        lines.append("End of log. You can safely delete this export after review.")
        return lines.joined(separator: "\n")
    }

    static func copyToPasteboard(_ actions: [AIAction]) {
        let text = exportAsText(actions)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
