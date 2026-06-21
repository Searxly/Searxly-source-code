//
//  ConversationContextManager.swift
//  Searxly
//
//  Moved into Chat/ as part of 2026 Local AI full rework (normal chatbot + user-called actions).
//  Original logic preserved with only header + minor comment updates.
//  Smart dynamic truncation for history based on attached files / RAG load / low-memory.
//  All on-device, private.
//

import Foundation

@MainActor
final class ConversationContextManager {

    private let manager: LocalIntelligenceManager

    init(manager: LocalIntelligenceManager) {
        self.manager = manager
    }

    convenience init() {
        self.init(manager: LocalIntelligenceManager.shared)
    }

    /// Rough but consistent token estimator. Apple on-device models are ~3-4 chars per token for English;
    /// we use a conservative 3.5 chars/token + overhead for roles/newlines/formatting.
    private func estimateTokens(_ text: String) -> Int {
        let chars = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        return max(1, (chars / 3) + (text.components(separatedBy: .newlines).count / 2) + 8)
    }

    /// Builds a compact, high-signal history string that respects a global token budget.
    /// Now truly token-aware (the previous turn-count + char truncation was insufficient and caused
    /// "Provided X tokens but max is 4096" after only 3-4 prompts when search/RAG/files were also injected).
    func buildHistoryString(
        from messages: [ChatMessage],
        attachedFilesCount: Int,
        ragItemCount: Int,
        hasCustomInstructions: Bool,
        tokenBudgetForHistory: Int = 2200   // Leave generous headroom for system rules + per-turn ctx + response
    ) -> String {
        // Start with the messages we are willing to consider (use compress for real token budget)
        let candidateMessages = compressHistoryIfNeeded(
            messages: messages,
            targetTokenBudget: tokenBudgetForHistory
        )

        // Still apply the previous dynamic turn caps on top of the token budget for extra safety
        var effectiveMaxTurns = manager.isHighPerformanceDevice ? 14 : 8
        if manager.preferences.lowMemoryMode {
            effectiveMaxTurns = 4
        } else if manager.isHighPerformanceDevice {
            effectiveMaxTurns = 12
        }

        let heavyContext = attachedFilesCount > 0 || ragItemCount > 3 || hasCustomInstructions
        if heavyContext {
            effectiveMaxTurns = max(2, effectiveMaxTurns / 2)
        }

        let recentTurns = candidateMessages.suffix(effectiveMaxTurns)

        var history = ""
        var used = 0
        for m in recentTurns where m.role != .system {
            let speaker = m.role == .user ? "User" : "Assistant"

            // Per-message char safety (defense in depth)
            let baseLen = manager.isHighPerformanceDevice ? 1200 : 800
            let maxLen = heavyContext ? (manager.isHighPerformanceDevice ? 600 : 450) : baseLen
            let text = m.text.count > maxLen
                ? String(m.text.prefix(maxLen)) + "... [truncated for context]"
                : m.text

            let line = "\(speaker): \(text)\n\n"
            let lineTokens = estimateTokens(line)
            if used + lineTokens > tokenBudgetForHistory && history.count > 0 {
                // Stop adding more history; the compress + suffix should have prevented most cases.
                break
            }
            history += line
            used += lineTokens
        }

        return history
    }

    /// Token-budget aware compressor. Keeps the most recent messages while staying under the budget.
    /// Always keeps at least the last 2 turns so the conversation doesn't become useless.
    /// This is now actively used by buildHistoryString (previously it was defined but never called).
    func compressHistoryIfNeeded(
        messages: [ChatMessage],
        targetTokenBudget: Int = 2200
    ) -> [ChatMessage] {
        var totalTokens = 0
        var kept: [ChatMessage] = []

        // Walk from newest to oldest, stop when we would exceed (but always keep a minimum tail)
        for m in messages.reversed() {
            if m.role == .system { continue }
            let est = estimateTokens(m.text)
            if totalTokens + est > targetTokenBudget && kept.count >= 2 {
                break
            }
            kept.insert(m, at: 0)
            totalTokens += est
        }

        return kept
    }
}
