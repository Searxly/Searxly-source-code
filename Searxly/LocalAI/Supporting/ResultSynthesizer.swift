//
//  ResultSynthesizer.swift
//  Searxly
//
//  Moved to Supporting/ during 2026 Local AI reorg.
//  One-shot grounded synthesis over private search result *snippets only* (Option A security decision).
//  Never receives raw page bodies. Responses are now stripped of any citation numbers or sources lists
//  to deliver straight-to-the-point answers (user request).
//  Reused by the manager when synthesisEnabled.
//

import Foundation

enum ResultSynthesizer {

    /// The main entry point. Returns nil on any failure or when the provider cannot be used.
    static func synthesize(
        query: String,
        results: [SearXNGResult],
        using provider: IntelligenceProvider
    ) async -> AISummary? {
        guard !results.isEmpty else { return nil }

        let searchResultsContext = AIPromptLibrary.numberedSourceBlock(from: results)
        let prompt = AIPromptLibrary.synthesis(query: query, numberedSources: searchResultsContext)

        let rawReply: String
        do {
            // For synthesis we use a one-shot generate (no instructions override needed beyond the prompt itself).
            rawReply = try await provider.generate(prompt: prompt, instructions: nil)
        } catch {
            print("[ResultSynthesizer] Generation failed: \(error)")
            return nil
        }

        var text = rawReply.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip any trailing Sources/References section and citation markers [1], [N], etc.
        // User wants straight-to-the-point answers, no citation style.
        text = ResponsePostProcessor.stripTrailingSourcesSectionForSynthesis(text)
        text = ResponsePostProcessor.stripCitationMarkersFromSynthesis(text)
        guard !text.isEmpty else { return nil }

        // Mechanical citations: build from the exact input results in order.
        // The prompt strictly tells the model to use [1], [2], ... so we can trust the indices.
        let citations: [Citation] = results.enumerated().map { index, result in
            Citation(
                id: index + 1,
                title: result.title,
                url: result.url,
                engine: result.engine
            )
        }

        return AISummary(
            query: query,
            text: text,
            citations: citations,
            generatedAt: Date(),
            estimatedTokens: nil // could estimate later if needed
        )
    }
}
