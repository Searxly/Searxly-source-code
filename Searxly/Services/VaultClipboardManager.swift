//
//  VaultClipboardManager.swift
//  Searxly
//
//  Tracks vault-owned clipboard copies and auto-clears them after a short window.
//  Also clears on vault lock when the pasteboard still holds our last copied value.
//

import AppKit
import Foundation

@MainActor
final class VaultClipboardManager {
    static let shared = VaultClipboardManager()

    /// Default auto-clear window (seconds). Chosen between 30–60s per security guidance.
    nonisolated static let defaultClearInterval: TimeInterval = 45

    private var scheduledClearTask: Task<Void, Never>?
    private var lastCopiedValue: String?

    private init() {}

    func copySensitive(_ value: String, clearAfter: TimeInterval = VaultClipboardManager.defaultClearInterval) {
        scheduledClearTask?.cancel()

        lastCopiedValue = value
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        // Mark as concealed so clipboard managers and Universal Clipboard skip storing/syncing it.
        pasteboard.setString(value, forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("com.apple.is-sensitive"))

        scheduledClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(clearAfter))
            guard !Task.isCancelled else { return }
            clearIfStillOurs()
        }
    }

    /// Clears the pasteboard only if it still contains the last vault-copied secret.
    func clearIfStillOurs() {
        scheduledClearTask?.cancel()
        scheduledClearTask = nil

        guard let last = lastCopiedValue else { return }
        let pasteboard = NSPasteboard.general
        if pasteboard.string(forType: .string) == last {
            pasteboard.clearContents()
        }
        lastCopiedValue = nil
    }
}