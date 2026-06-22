//
//  ResponsePostProcessor.swift
//  Searxly
//
//  Moved into Chat/ during 2026 Local AI rework (chatbot-first + organized folders).
//  Centralized, deterministic post-processing for every on-device generation.
//  Strips priming/markers, fixes dry starters, applies light style, respects low-memory.
//  Reused by ConversationEngine, the chat sheet, suggestions, synthesis, etc.
//  All changes here are local-only and never add new facts.
//

import Foundation

struct PostProcessingContext: Equatable {
    let hasCustomInstructions: Bool
    let usedTools: Bool
    let isToolFollowUp: Bool
    let isSuggestion: Bool
    let lowMemoryMode: Bool
    /// When true, keep `[1]`, `[2]` citation markers (and a trailing sources section) intact.
    /// Used by the cloud grounded path, which deliberately cites clickable sources. Defaults false
    /// so the on-device "straight-to-the-point, no citations" behavior is unchanged everywhere else.
    var preserveCitations: Bool = false

    // Convenience for common cases
    static let `default` = PostProcessingContext(
        hasCustomInstructions: false,
        usedTools: false,
        isToolFollowUp: false,
        isSuggestion: false,
        lowMemoryMode: false
    )
}

enum ResponsePostProcessor {

    /// Main entry point. Takes raw model output and context, returns polished response.
    /// Always safe: never adds new facts, never removes user-approved content, keeps privacy language.
    /// Enhanced in audit pass to aggressively strip priming artifacts (e.g. "Assistant:") so the
    /// on-device model cannot leak internal markers or the priming we use for completion.
    static func process(_ raw: String, context: PostProcessingContext) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            return context.isSuggestion
                ? "What would you like to explore next?"
                : "I didn't get a clear response. Want to try again?"
        }

        // 0. Strip common completion priming / role leakage that smaller on-device models sometimes emit
        // even when instructed not to. Do this very early.
        cleaned = stripPrimingAndRolePrefixes(from: cleaned)

        // 1. Remove any accidental tool markers or internal leakage (safety)
        cleaned = removeToolMarkers(from: cleaned)

        // 1b. Aggressively strip any trailing "Sources / References / Bibliography" section
        // AND any citation markers like [1], [2], (1), 1., etc. The user wants straight-to-the-point
        // answers with no citation style at all — EXCEPT the cloud grounded path, which keeps [n]
        // markers so they line up with the clickable source chips.
        if !context.preserveCitations {
            cleaned = stripTrailingSourcesSection(from: cleaned)
            cleaned = stripCitationMarkers(from: cleaned)
        }

        // 2. Fix common dry/technical/robotic starters (quality + naturalness)
        cleaned = fixDryStarters(cleaned, context: context)

        // 3. Light style application based on context (respects custom instructions indirectly via prompt,
        //    but reinforces here for consistency)
        if context.hasCustomInstructions && !context.isSuggestion {
            cleaned = applyLightStylePolish(cleaned, context: context)
        }

        // 4. Final safety/quality guards
        if context.lowMemoryMode {
            cleaned = truncateIfTooLong(cleaned, maxChars: 1200)
        }

        // Ensure it doesn't end mid-sentence in a weird way for tool follow-ups
        if context.isToolFollowUp && !cleaned.hasSuffix(".") && !cleaned.hasSuffix("!") && !cleaned.hasSuffix("?") {
            if let last = cleaned.last, last.isLetter {
                cleaned += "."
            }
        }

        return cleaned
    }

    // MARK: - Private helpers (easy to extend/test)

    private static func removeToolMarkers(from text: String) -> String {
        // Remove any leaked TOOL_REQUEST or similar (shouldn't happen with good prompts, but belt-and-suspenders)
        var result = text
        result = result.replacingOccurrences(of: "TOOL_REQUEST:", with: "", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "tool_request:", with: "", options: .caseInsensitive)
        // Remove any obvious internal markers
        result = result.replacingOccurrences(of: "Tool result:", with: "", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "web_search result", with: "search result", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "open_website", with: "", options: .caseInsensitive)
        // Safety net: strip identity/privacy boilerplate the model sometimes emits despite prompt rules.
        let boilerplate = "I am a private on-device AI running locally on your Mac"
        if result.lowercased().contains(boilerplate.lowercased()) {
            result = result.replacingOccurrences(of: "I am a private on-device AI running locally on your Mac. Everything stays on your device, zero data leaves the Mac.", with: "", options: .caseInsensitive)
            result = result.replacingOccurrences(of: boilerplate, with: "", options: .caseInsensitive)
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Strip "I am Searxly Local..." / "I'm Searxly Local..." preamble that Ollama models output
        // at the start of responses, typically: "I am Searxly Local, the private assistant inside this
        // browser. This session I'm powered by Ollama with the model '...' you chose in settings."
        let lower = result.lowercased()
        if lower.hasPrefix("i am searxly local") || lower.hasPrefix("i'm searxly local") {
            if let settingsEnd = lower.range(of: "you chose in settings.") {
                // Strip the full two-sentence intro block
                result = String(result[settingsEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let period = result.firstIndex(of: ".") {
                // Strip just the first sentence
                let afterPeriod = result.index(after: period)
                result = String(result[afterPeriod...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripCitationMarkersFromSynthesis(_ text: String) -> String {
        return stripCitationMarkers(from: text)
    }

    private static func stripCitationMarkers(from text: String) -> String {
        var result = text

        // Remove inline citation markers like [1], [2], (1), (2), [1,2], 1. etc.
        // User wants no citation style whatsoever.
        let citationPatterns = [
            #"\[\d+(?:,\s*\d+)*\]"#,   // [1], [1,2], [1, 2]
            #"\(\d+(?:,\s*\d+)*\)"#,   // (1), (1,2)
            #"\[\s*\d+\s*\]"#,         // [ 1 ]
            #"\(\s*\d+\s*\)"#,         // ( 1 )
            #"\b\d+\.\s+(?=[A-Z])"#,   // 1. at start of sentence (common in lists)
            #"\s*\[\s*\d+\s*\]\s*"#,   // loose [1]
        ]

        for pattern in citationPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
            }
        }

        // Clean up extra spaces/punctuation left behind
        result = result.replacingOccurrences(of: "  ", with: " ")
        result = result.replacingOccurrences(of: " .", with: ".")
        result = result.replacingOccurrences(of: " ,", with: ",")
        result = result.replacingOccurrences(of: "  ", with: " ")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes common trailing "Sources / References / Bibliography / Citations" blocks.
    /// Handles the model emitting them even when instructed not to.
    /// This keeps the visible response clean; inline [N] citations remain and are enhanced by the UI.
    static func stripTrailingSourcesSectionForSynthesis(_ text: String) -> String {
        // Public wrapper for synthesis path
        return stripTrailingSourcesSection(from: text)
    }

    private static func stripTrailingSourcesSection(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let sourceHeaders = [
            "sources:", "sources", "references:", "references",
            "bibliography:", "bibliography", "citations:", "citations",
            "source list:", "reference list:", "further reading:"
        ]

        let lower = result.lowercased()

        for header in sourceHeaders {
            if let range = lower.range(of: header, options: .backwards) {
                // Only strip if it looks like a trailing section (near the end, and followed by list-like content or end of string)
                let afterHeader = result[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if afterHeader.isEmpty || afterHeader.hasPrefix("[") || afterHeader.hasPrefix("1.") || afterHeader.hasPrefix("-") || afterHeader.hasPrefix("•") {
                    // Check that this section is in the last ~40% of the text to avoid stripping mid-response "sources" mentions
                    let headerStartIndex = result.distance(from: result.startIndex, to: range.lowerBound)
                    if headerStartIndex > result.count / 2 {
                        result = String(result[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fixDryStarters(_ text: String, context: PostProcessingContext) -> String {
        var cleaned = text
        let lower = cleaned.lowercased()

        let dryStarters = [
            "the search results", "according to the", "the results show", "from the search",
            "search results for", "action ", "i have ", "i used ", "based on the",
            "here are the", "the tool returned", "according to your", "the following",
            "i searched", "from private search", "the private search", "web search results"
        ]

        if dryStarters.contains(where: { lower.hasPrefix($0) }) {
            if let first = cleaned.first {
                let naturalPrefix = context.isToolFollowUp
                    ? "I pulled the info and "
                    : "Here's what I found: "
                cleaned = naturalPrefix + String(first).lowercased() + String(cleaned.dropFirst())
            }
        }

        // Additional naturalization for tool follow-ups (web_search or open_website)
        if context.isToolFollowUp {
            if lower.hasPrefix("i pulled some fresh") || lower.hasPrefix("from a quick") {
                // already good, leave it
            } else if lower.contains("tool") && lower.contains("result") {
                cleaned = cleaned.replacingOccurrences(of: "tool result", with: "results", options: .caseInsensitive)
            }
            // Remove any remaining self-reference to the specific tool names
            cleaned = cleaned.replacingOccurrences(of: "web search results", with: "the results", options: .caseInsensitive)
            cleaned = cleaned.replacingOccurrences(of: "from the search", with: "from what I found", options: .caseInsensitive)
        }

        return cleaned
    }

    private static func applyLightStylePolish(_ text: String, context: PostProcessingContext) -> String {
        var cleaned = text

        // If user set custom instructions, the prompt already guides the model.
        // Here we do light reinforcement only (never override facts).
        if context.hasCustomInstructions {
            // Example: if user wants concise, trim redundant phrases (conservative)
            if context.lowMemoryMode || text.count > 1500 {
                // very light trim of obvious repetition
                let sentences = cleaned.split(separator: ".").map { String($0).trimmingCharacters(in: .whitespaces) }
                if sentences.count > 6 {
                    cleaned = sentences.prefix(5).joined(separator: ". ") + "."
                }
            }
        }

        return cleaned
    }

    private static func truncateIfTooLong(_ text: String, maxChars: Int) -> String {
        if text.count <= maxChars { return text }
        let prefix = text.prefix(maxChars)
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace]) + "..."
        }
        return String(prefix) + "..."
    }

    /// Strips leading role/priming artifacts that on-device models sometimes emit despite
    /// strict instructions in the prompt (e.g. because we prime with "\nAssistant:" for completion).
    /// This is critical so the final user-visible text never contains "Assistant:", internal markers,
    /// or repeated priming.
    /// Public so the chat sheet can use the exact same early strip before TOOL_REQUEST parsing.
    static func stripPrimingAndRolePrefixesForParsing(_ text: String) -> String {
        return stripPrimingAndRolePrefixes(from: text)
    }

    private static func stripPrimingAndRolePrefixes(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Common prefixes the model might echo back
        let prefixesToStrip = [
            "assistant:", "assistant :", "Assistant:", "Assistant :",
            "ai:", "AI:", "model:", "Model:",
            "response:", "Response:",
            "here is the", "Here is the"
        ]

        let lower = result.lowercased()
        for p in prefixesToStrip {
            if lower.hasPrefix(p.lowercased()) {
                // Remove the prefix (case-insensitive match) and trim again
                let prefixLen = p.count
                result = result.dropFirst(prefixLen).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // Also strip a leading "Assistant" or "assistant" word if followed by punctuation or space
        if result.lowercased().hasPrefix("assistant") {
            if let firstSpace = result.firstIndex(of: " ") {
                result = result[firstSpace...].trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let firstPunct = result.firstIndex(where: { ".,:;!?".contains($0) }) {
                result = result[firstPunct...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return result
    }
}
