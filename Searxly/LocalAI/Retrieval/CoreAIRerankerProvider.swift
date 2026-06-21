//
//  CoreAIRerankerProvider.swift
//  Searxly
//
//  Moved to Retrieval/ in the 2026 Local AI reorg.
//  High priority #2: Core AI reranker (second-stage precision for RAG).
//  Reuses the exact same pattern as CoreAIEmbeddingProvider (conditional import, user .aimodel,
//  mocks for dev, unload, factory from prefs).
//  A reranker scores (query, doc) pairs for relevance. After first-stage retrieval (keyword or
//  embedding) we take top-M (higher recall), rerank the pairs, and keep the final top-k for the LLM.
//  The real Core AI inference is the obvious extension (identical to the embedding sibling).
//

import Foundation

protocol RerankerProvider: AnyObject {
    func score(query: String, document: String) async -> Double?
    func unload()
}

final class CoreAIRerankerProvider: RerankerProvider {

    private var loadedModel: Any?   // CoreAI runtime model when real .aimodel supplied
    private var lastPath: String?

    private let modelPath: String?

    init(modelPath: String?) {
        self.modelPath = modelPath
    }

    func score(query: String, document: String) async -> Double? {
        guard resolvedPath != nil, !query.isEmpty, !document.isEmpty else {
            return mockScore(query: query, document: document)
        }

        #if canImport(CoreAI) && arch(arm64)
        if #available(macOS 27.0, *) {
            // TODO: real Core AI pair scoring here (load once, loadFunction("rerank" or first program),
            // build input NDArray from (query, doc) features per your export recipe, extract float score).
            // For now fall through to mock so the RAGEngine + manager + settings pipeline is complete.
        }
        #endif

        return mockScore(query: query, document: document)
    }

    func unload() {
        #if canImport(CoreAI) && arch(arm64)
        loadedModel = nil
        #endif
        lastPath = nil
    }

    private var resolvedPath: String? {
        guard var p = modelPath, !p.isEmpty else { return nil }
        if p.hasPrefix("~") { p = NSString(string: p).expandingTildeInPath }
        return p
    }

    private func mockScore(query: String, document: String) -> Double {
        // Lightweight deterministic pair score (projection + cosine of the two vectors).
        // Good enough to exercise the rerank path and see different ordering vs pure first-stage.
        let qv = project(query)
        let dv = project(document)
        var dot: Float = 0, nq: Float = 0, nd: Float = 0
        for i in 0..<qv.count {
            dot += qv[i] * dv[i]
            nq += qv[i] * qv[i]
            nd += dv[i] * dv[i]
        }
        let denom = sqrt(nq) * sqrt(nd) + 1e-6
        return Double(dot / denom)
    }

    private func project(_ text: String) -> [Float] {
        let norm = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var v = Array(repeating: Float(0), count: 128)
        let bytes = Array(norm.utf8)
        for (i, b) in bytes.enumerated() {
            let idx = (i * 17 + Int(b)) % 128
            v[idx] += Float(b) / 255.0
        }
        let n = sqrt(v.reduce(0) { $0 + $1*$1 }) + 1e-6
        return v.map { $0 / n }
    }

    static func make(preferences: AIPreferences) -> CoreAIRerankerProvider? {
        guard preferences.rerankerEnabled else { return nil }
        return CoreAIRerankerProvider(modelPath: preferences.coreAIRerankerModelPath)
    }
}
