//
//  ChatAttachment.swift
//  Searxly
//
//  Moved to Supporting/ in the 2026 Local AI folder reorg (chatbot enhancements preserved).
//  Represents a user-explicitly-chosen local file (PDF/text/Markdown) attached only for the
//  lifetime of the current chat sheet. Content is extracted once, kept in memory, injected
//  into prompts as trusted personal context, and never persisted or sent anywhere.
//  This is the safe way to combine "my own notes" with fresh private web research.
//

import Foundation

struct ChatAttachment: Identifiable, Equatable {
    let id: UUID
    let filename: String
    let sizeBytes: Int
    /// Extracted plain text (sanitized / truncated by the caller before storage).
    /// This is what gets injected into the on-device model prompt for the session.
    let extractedText: String
    /// Optional hint about how the user provided it (e.g. "local file", future "from bookmark").
    let sourceHint: String?

    /// Human-readable size (e.g. "12 KB").
    var sizeDescription: String {
        let kb = Double(sizeBytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.0f KB", kb)
        } else {
            return String(format: "%.1f MB", kb / 1024.0)
        }
    }

    init(filename: String, sizeBytes: Int, extractedText: String, sourceHint: String? = "local file") {
        self.id = UUID()
        self.filename = filename
        self.sizeBytes = sizeBytes
        self.extractedText = extractedText
        self.sourceHint = sourceHint
    }
}

// Small helper to keep character budgets sane for the model context.
extension ChatAttachment {
    /// Returns a safe excerpt if the full extracted text would be too large.
    /// The caller (LocalAIChatSheet) decides the global budget across all attachments.
    func excerpt(maxChars: Int) -> String {
        let text = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count <= maxChars {
            return text
        }
        let prefix = text.prefix(maxChars)
        return String(prefix) + "\n... [truncated for context budget]"
    }
}
