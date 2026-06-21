//
//  QueryRewriter.swift
//  Searxly
//
//  Moved to Supporting/ as part of 2026 Local AI rework (normal on-device chatbot + clean organization).
//  Thin wrapper around the current IntelligenceProvider for one-shot query improvement.
//  Only called when the user has explicitly enabled the rewrite feature in settings.
//  All work stays on-device.
//

import Foundation

enum QueryRewriter {

    /// The only public entry. Returns the original unchanged on any failure or when the provider is a stub.
    static func rewrite(_ raw: String, using provider: IntelligenceProvider) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }

        let prompt = AIPromptLibrary.queryRewrite(userQuery: trimmed)

        do {
            let improved = try await provider.generate(prompt: prompt, instructions: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Basic sanity: if the model returned something empty or absurdly long, fall back.
            if improved.isEmpty || improved.count > trimmed.count * 4 {
                return trimmed
            }
            return improved
        } catch {
            // Silent fallback is intentional for a privacy tool — better to search with the original
            // than to surface an error for a nice-to-have enhancement.
            return trimmed
        }
    }
}
