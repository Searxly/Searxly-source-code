//
//  RAGEngine.swift
//  Searxly
//
//  Moved to Retrieval/ during the 2026 Local AI complete reorg (chatbot-first, user-called actions, organized folders).
//  In-memory private RAG over the user's own history + bookmarks (titles/URLs/dates only — never full page bodies).
//  Supports keyword, Core AI semantic (embeddings), and Core AI reranker (pair scoring) paths.
//  Rebuilt on demand or on explicit settings action; auto-heals in the manager.
//  Everything stays on the Mac.
//

import Foundation

final class RAGEngine {
    private var index: [RAGItem] = []

    // Semantic (Core AI) support. When a provider is supplied and semantic is enabled,
    // we store parallel pre-computed embeddings and use cosine + recency for retrieval.
    private var embeddingProvider: EmbeddingProvider?
    private var itemEmbeddings: [UUID: [Float]] = [:]   // keyed by RAGItem.id for stability across rebuilds
    private var usingSemantic: Bool = false

    // High priority #2: optional Core AI reranker for second-stage precision.
    private var reranker: RerankerProvider?
    private var usingReranker: Bool = false

    /// Rebuild the in-memory index from the user's history and bookmarks.
    /// Call this when RAG is enabled, after data changes, or on explicit "Rebuild".
    /// Only titles, URLs, and dates are used — no full page bodies.
    ///
    /// When a non-nil `embeddingProvider` is passed (and preferences.semanticRAGEnabled),
    /// we compute on-device embeddings (Core AI when available, mock otherwise) for every item
    /// so retrieve() can do proper semantic + recency scoring.
    ///
    /// reranker: optional Core AI reranker for post-retrieval precision (High #2).
    func rebuildIndex(from history: [HistoryItem], bookmarks: [BookmarkItem], preferences: AIPreferences, embeddingProvider: EmbeddingProvider? = nil, reranker: RerankerProvider? = nil) {
        index.removeAll()
        itemEmbeddings.removeAll()
        self.embeddingProvider = embeddingProvider
        self.usingSemantic = (embeddingProvider != nil) && preferences.semanticRAGEnabled
        self.reranker = reranker
        self.usingReranker = (reranker != nil) && preferences.rerankerEnabled

        let cutoff = preferences.ragRecencyCutoff ?? .distantPast

        if preferences.ragIncludeHistory {
            for item in history where item.date >= cutoff {
                let ragItem = RAGItem(
                    id: UUID(), // fresh UUID per rebuild (index is ephemeral in-memory only; stable identity not required across rebuilds)
                    source: .history,
                    title: item.title,
                    url: item.url,
                    date: item.date,
                    snippet: nil
                )
                index.append(ragItem)
            }
        }

        if preferences.ragIncludeBookmarks {
            for item in bookmarks where item.dateAdded >= cutoff {
                let ragItem = RAGItem(
                    id: UUID(), // fresh UUID per rebuild (index is ephemeral in-memory only)
                    source: .bookmark,
                    title: item.title,
                    url: item.url,
                    date: item.dateAdded,
                    snippet: nil
                )
                index.append(ragItem)
            }
        }

        // Sort by date desc for recency bias (retrieval will re-score)
        index.sort { $0.date > $1.date }

        // Soft cap
        if index.count > preferences.ragMaxItems {
            index = Array(index.prefix(preferences.ragMaxItems))
        }

        // Pre-compute embeddings for semantic path (async is fine; we fire-and-forget per item here
        // because rebuild is not on the hot path and N is small).
        if usingSemantic, let provider = embeddingProvider {
            Task { [weak self] in
                guard let self else { return }
                for ragItem in self.index {
                    if let vec = await provider.embed("\(ragItem.title) \(ragItem.url)") {
                        self.itemEmbeddings[ragItem.id] = vec
                    }
                }
            }
        }
    }

    /// Retrieve top-k relevant items for the query.
    /// Keyword path (original): term overlap in title/URL + recency.
    /// Semantic path (Core AI or mock): cosine similarity of query embedding vs precomputed item embeddings + recency.
    func retrieve(query: String, k: Int) async -> [RAGItem] {
        guard !index.isEmpty else { return [] }

        // Semantic path (preferred when we have embeddings for the items)
        if usingSemantic, let provider = embeddingProvider, let qvec = await provider.embed(query) {
            // Sequential on-demand embed + cache (safe, no data races on itemEmbeddings).
            // RAG N is small; parallel task group caused Swift 6 isolation violations / data races
            // when mutating the dict and calling cosineSimilarity from concurrent addTask closures.
            // Sequential await is simple and sufficient here.
            var scored: [(item: RAGItem, score: Double)] = []
            for item in index {
                var ivec = itemEmbeddings[item.id]
                if ivec == nil {
                    // On-demand embed + cache (covers the fire-and-forget precompute in rebuildIndex
                    // and makes first retrieve after a semantic toggle see real vectors quickly).
                    if let fresh = await provider.embed("\(item.title) \(item.url)") {
                        itemEmbeddings[item.id] = fresh
                        ivec = fresh
                    }
                }
                var score = 0.0
                if let v = ivec {
                    score = cosineSimilarity(qvec, v) * 10.0
                }
                let ageDays = max(0, Date().timeIntervalSince(item.date) / (3600 * 24))
                let recency = exp(-ageDays / 90.0)
                score += recency * 3.0
                scored.append((item, score))
            }

            let top = scored
                .sorted { $0.score > $1.score }
                .prefix(k)
                .map { $0.item }
            return Array(top)
        }

        // Original keyword path (fallback or when semantic disabled)
        let lowerQuery = query.lowercased()
        let rawTerms = lowerQuery.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !$0.isEmpty }

        // Stop words: ignore common words so general questions like "who is elon musk"
        // don't match unrelated history items that happen to contain "is", "what", etc.
        let stopWords: Set<String> = ["who", "what", "where", "when", "why", "how", "is", "are", "was", "were", "be", "been", "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "from", "about", "this", "that", "these", "those"]
        let terms = rawTerms.filter { !stopWords.contains($0) }

        guard !terms.isEmpty else {
            // No significant terms after stopword filtering (very generic query) — return no RAG.
            // This prevents leaking recent unrelated history into general knowledge questions.
            return []
        }

        let scored: [(item: RAGItem, score: Double)] = index.compactMap { item in
            var termScore = 0.0
            let titleLower = item.title.lowercased()
            let urlLower = item.url.lowercased()

            for term in terms {
                if titleLower.contains(term) { termScore += 2.0 }
                if urlLower.contains(term) { termScore += 1.5 }
            }

            // Only consider items that have at least one meaningful term match.
            // Pure recency without any term overlap is not "relevant" for RAG.
            guard termScore > 0 else { return nil }

            // Recency boost (newer = higher score, exponential decay) — only for matched items
            let ageDays = max(0, Date().timeIntervalSince(item.date) / (3600 * 24))
            let recency = exp(-ageDays / 90.0) // ~3 month half-life
            let score = termScore + recency * 3.0

            return (item, score)
        }

        var candidates = scored.sorted { $0.score > $1.score }

        // High #2: reranker (Core AI) — take a larger recall set and re-score pairs for better precision.
        if usingReranker, let rerankerProv = reranker, !candidates.isEmpty {
            let recallM = min(candidates.count, max(k * 3, 20))
            let recallSet = Array(candidates.prefix(recallM))
            var reranked: [(item: RAGItem, score: Double)] = []
            for c in recallSet {
                // Prefer the live provider (real Core AI model once a .aimodel is supplied).
                // Falls back to the deterministic mock projection if the provider returns nil.
                let providerScore = await rerankerProv.score(query: query, document: "\(c.item.title) \(c.item.url)")
                let s = providerScore ?? Self.pairScore(query: query, doc: "\(c.item.title) \(c.item.url)")
                reranked.append((c.item, c.score * 0.3 + s * 10.0))
            }
            candidates = reranked.sorted { $0.score > $1.score }
        } else if usingReranker, !candidates.isEmpty {
            // usingReranker was true but no provider instance (shouldn't normally happen); fall back to internal mock.
            let recallM = min(candidates.count, max(k * 3, 20))
            let recallSet = Array(candidates.prefix(recallM))
            var reranked: [(item: RAGItem, score: Double)] = []
            for c in recallSet {
                let s = Self.pairScore(query: query, doc: "\(c.item.title) \(c.item.url)")
                reranked.append((c.item, c.score * 0.3 + s * 10.0))
            }
            candidates = reranked.sorted { $0.score > $1.score }
        }

        let top = candidates.prefix(k).map { $0.item }
        return Array(top)
    }

    var count: Int { index.count }

    /// For audit / transparency in settings.
    func allItems() -> [RAGItem] {
        index
    }

    func clear() {
        index.removeAll()
        itemEmbeddings.removeAll()
        embeddingProvider = nil
        usingSemantic = false
        reranker = nil
        usingReranker = false
    }

    /// Call after preferences change (e.g. semantic toggle) or when user supplies/changes the model path.
    func setEmbeddingProvider(_ provider: EmbeddingProvider?) {
        self.embeddingProvider = provider
        self.usingSemantic = (provider != nil)
        // Next rebuild will (re)compute embeddings if usingSemantic.
    }

    /// Call after prefs change for the reranker.
    func setReranker(_ r: RerankerProvider?) {
        self.reranker = r
        self.usingReranker = (r != nil)
    }

    // Lightweight pair scorer (same as the stub in CoreAIRerankerProvider) for the rerank step
    // when no real .aimodel is supplied yet. Produces stable scores so ordering changes vs first-stage
    // can be observed.
    private static func pairScore(query: String, doc: String) -> Double {
        func project(_ t: String) -> [Float] {
            let n = t.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            var v = Array(repeating: Float(0), count: 128)
            let b = Array(n.utf8)
            for (i, c) in b.enumerated() {
                let idx = (i * 17 + Int(c)) % 128
                v[idx] += Float(c) / 255.0
            }
            let norm = sqrt(v.reduce(0) { $0 + $1 * $1 }) + 1e-6
            return v.map { $0 / norm }
        }
        let qv = project(query)
        let dv = project(doc)
        var dot: Float = 0, nq: Float = 0, nd: Float = 0
        for i in 0..<qv.count {
            dot += qv[i] * dv[i]
            nq += qv[i] * qv[i]
            nd += dv[i] * dv[i]
        }
        return Double(dot / (sqrt(nq) * sqrt(nd) + 1e-6))
    }
}
