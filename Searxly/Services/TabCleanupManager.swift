//
//  TabCleanupManager.swift
//  Searxly
//
//  "Auto Tab Cleanup" — a powerful, opt-in feature (never on by default)
//  that automatically removes old or excessive tabs to reduce clutter.
//
//  Designed to complement (not replace) Tab Hibernation:
//  - Hibernation = unload web content to save RAM (tab stub stays)
//  - Cleanup     = actually delete the tab from the session (more aggressive declutter)
//
//  Features:
//  - Time-based inactivity rules (with separate stricter rule for Private tabs)
//  - Hard cap on total tab count (close oldest unused first)
//  - Lifecycle rules (on app quit)
//  - Never touches the currently active tab
//  - Posts notifications so the UI can give subtle feedback
//  - Fully controllable from Settings only
//

import Foundation
import os
import SwiftUI

extension Notification.Name {
    static let tabsWereAutoCleaned = Notification.Name("Searxly.TabsWereAutoCleaned")
}

/// Result of a cleanup pass (for UI feedback)
struct TabCleanupResult {
    let removedCount: Int
    let reason: String
}

@MainActor
@Observable
final class TabCleanupManager {
    static let shared = TabCleanupManager()

    // MARK: - Live Configuration (loaded from Persistence, updated by Settings)

    var isEnabled: Bool = false
    var closeUnusedAfter: TimeInterval = 86400          // 24 hours
    var closePrivateAfter: TimeInterval = 3600          // 1 hour
    var closeWhenExceedsCount: Int = 0                  // 0 = disabled
    var closeBackgroundTabsOnQuit: Bool = false

    private init() {
        loadConfiguration()
    }

    /// Reloads preferences from disk (called on launch and after Settings changes)
    func loadConfiguration() {
        let data = Persistence.load()
        isEnabled = data.autoTabCleanupEnabled
        closeUnusedAfter = TimeInterval(data.autoCloseUnusedAfterSeconds)
        closePrivateAfter = TimeInterval(data.autoClosePrivateTabsAfterSeconds)
        closeWhenExceedsCount = data.autoCloseWhenExceedsTabCount
        closeBackgroundTabsOnQuit = data.autoCloseBackgroundTabsOnQuit
    }

    /// Persists the current in-memory settings back to AppData.json
    func saveConfiguration() {
        var current = Persistence.load()
        current.autoTabCleanupEnabled = isEnabled
        current.autoCloseUnusedAfterSeconds = Int(closeUnusedAfter)
        current.autoClosePrivateTabsAfterSeconds = Int(closePrivateAfter)
        current.autoCloseWhenExceedsTabCount = closeWhenExceedsCount
        current.autoCloseBackgroundTabsOnQuit = closeBackgroundTabsOnQuit
        Persistence.save(current)
    }

    // MARK: - Public Cleanup API

    /// Performs a full cleanup pass according to current rules.
    /// Returns a result describing what happened (for optional UI toast / log).
    @discardableResult
    func performCleanup(currentTab: BrowserTab?, among tabs: inout [BrowserTab]) -> TabCleanupResult {
        guard isEnabled else { return TabCleanupResult(removedCount: 0, reason: "Disabled") }

        let beforeCount = tabs.count
        var removed = 0
        let now = Date()

        // Collect candidates first so we can pause media *before* dropping the BrowserTab
        // (and thus its WKWebView). Direct removeAll used to bypass pauseAllMediaForClose,
        // which is why YT (and other) tabs could keep playing audio after auto-clean.
        var toPause: [BrowserTab] = []

        // 1. Time-based cleanup (standard tabs)
        if closeUnusedAfter > 0 {
            let cutoff = now.addingTimeInterval(-closeUnusedAfter)
            let candidates = tabs.filter { tab in
                guard tab.id != currentTab?.id else { return false }
                if tab.kind != .web { return false }
                let lastAccess = TabHibernationManager.shared.lastAccessTime(for: tab) ?? .distantPast
                return lastAccess < cutoff && !tab.isPrivate
            }
            toPause.append(contentsOf: candidates)
            tabs.removeAll { tab in
                guard tab.id != currentTab?.id else { return false }
                if tab.kind != .web { return false }
                let lastAccess = TabHibernationManager.shared.lastAccessTime(for: tab) ?? .distantPast
                let shouldRemove = lastAccess < cutoff && !tab.isPrivate
                if shouldRemove { removed += 1 }
                return shouldRemove
            }
        }

        // 2. Time-based cleanup (private tabs — usually stricter)
        if closePrivateAfter > 0 {
            let cutoff = now.addingTimeInterval(-closePrivateAfter)
            let candidates = tabs.filter { tab in
                guard tab.id != currentTab?.id else { return false }
                if tab.kind != .web { return false }
                let lastAccess = TabHibernationManager.shared.lastAccessTime(for: tab) ?? .distantPast
                return lastAccess < cutoff && tab.isPrivate
            }
            toPause.append(contentsOf: candidates)
            tabs.removeAll { tab in
                guard tab.id != currentTab?.id else { return false }
                if tab.kind != .web { return false }
                let lastAccess = TabHibernationManager.shared.lastAccessTime(for: tab) ?? .distantPast
                let shouldRemove = lastAccess < cutoff && tab.isPrivate
                if shouldRemove { removed += 1 }
                return shouldRemove
            }
        }

        // 3. Hard cap on total tab count (close oldest unused first, after the time rules)
        if closeWhenExceedsCount > 0 && tabs.count > closeWhenExceedsCount {
            let excess = tabs.count - closeWhenExceedsCount

            // Sort background tabs by last access (oldest first). Only web tabs are eligible.
            var background = tabs.filter { $0.id != currentTab?.id && $0.kind == .web }
            background.sort { lhs, rhs in
                let l = TabHibernationManager.shared.lastAccessTime(for: lhs) ?? .distantPast
                let r = TabHibernationManager.shared.lastAccessTime(for: rhs) ?? .distantPast
                return l < r
            }

            let toRemove = Array(background.prefix(excess))
            toPause.append(contentsOf: toRemove)
            let idsToRemove = Set(toRemove.map { $0.id })

            tabs.removeAll { idsToRemove.contains($0.id) }
            removed += toRemove.count
        }

        // Pause (and schedule blank load) on everything we are about to drop.
        // This covers the auto-clean paths that previously bypassed BrowserState.closeTab.
        for tab in toPause where tab.kind == .web {
            tab.pauseAllMediaForClose()
        }

        let finalRemoved = beforeCount - tabs.count

        if finalRemoved > 0 {
            let reason = buildReasonString(removed: finalRemoved)
            postCleanupNotification(count: finalRemoved, reason: reason)

            // Keep stats fresh
            TabHibernationManager.shared.currentStats(among: tabs)
        }

        return TabCleanupResult(removedCount: finalRemoved, reason: buildReasonString(removed: finalRemoved))
    }

    /// Special fast path used on app termination.
    /// Only acts if the user enabled "close background tabs on quit".
    func performQuitCleanup(currentTab: BrowserTab?, among tabs: inout [BrowserTab]) {
        guard isEnabled, closeBackgroundTabsOnQuit else { return }

        let before = tabs.count

        // Pause media on the background tabs we are about to nuke (same reason as performCleanup).
        let toPause = tabs.filter { $0.id != currentTab?.id && $0.kind == .web }
        for tab in toPause {
            tab.pauseAllMediaForClose()
        }

        tabs.removeAll { $0.id != currentTab?.id }

        let removed = before - tabs.count
        if removed > 0 {
            postCleanupNotification(count: removed, reason: "App quit")
        }
    }

    // MARK: - Helpers

    private func buildReasonString(removed: Int) -> String {
        if closeWhenExceedsCount > 0 {
            return "tab limit"
        } else if closeUnusedAfter > 0 || closePrivateAfter > 0 {
            return "inactivity"
        } else {
            return "automatic cleanup"
        }
    }

    private func postCleanupNotification(count: Int, reason: String) {
        NotificationCenter.default.post(
            name: .tabsWereAutoCleaned,
            object: nil,
            userInfo: ["count": count, "reason": reason]
        )
        Log.web.info("[AutoCleanup] Removed \(count) tab(s) due to \(reason)")
    }

    /// Convenience for the new tab creation path (count-based limit)
    func shouldPreventNewTabDueToLimit(currentCount: Int) -> Bool {
        guard isEnabled, closeWhenExceedsCount > 0 else { return false }
        return currentCount >= closeWhenExceedsCount
    }
}
