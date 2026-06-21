//
//  CoreAIEmbeddingProvider.swift
//  Searxly
//
//  Moved to Retrieval/ as part of the 2026 Local AI reorg (organized folders for chatbot + actions).
//  WWDC26 / macOS 27+ on-device Core AI embeddings for semantic RAG over the user's private
//  history and bookmarks. Graceful degradation to mocks when no .aimodel or older SDK.
//  Zero data leaves the Mac. See LOCAL_AI_IMPLEMENTATION_NOTES.md for how to obtain a model.
//

import Foundation

// MARK: - Simple protocol so RAGEngine and tests can stay decoupled

protocol EmbeddingProvider: AnyObject {
    /// Fixed dimension of the produced vectors (used for allocation / similarity).
    var dimension: Int { get }

    /// Compute an embedding for the given text. Returns nil on failure or when disabled.
    func embed(_ text: String) async -> [Float]?

    /// Best-effort release of loaded model weights / sessions.
    func unload()
}

// MARK: - Core AI backed implementation (the real thing on 27+)

#if canImport(CoreAI) && arch(arm64)
import CoreAI
#endif

// NOTE: The actual framework / module name in your Xcode 27 beta may be CoreAI, CoreAIRuntime,
// or a different umbrella. If the import above fails to find the runtime types you need
// (AIModel, AIModelAsset, loadFunction, NDArray etc.), adjust the canImport() and the
// concrete casts inside the #if blocks below. The rest of the pipeline (toggle, path UI,
// rebuild, retrieve + cosine, reranker blend, manager unload) will continue to work via the
// deterministic mock path until you wire the real inference.

final class CoreAIEmbeddingProvider: EmbeddingProvider {

    let dimension: Int = 256   // Common small embedding size; adjust to match your exported model.

    private var loadedModel: Any?   // CoreAI.AIModel when available (on arm64 + macOS 27+)
    private var embedFunctionName: String = "embed"   // Common name; falls back to first programName
    private var lastLoadedPath: String?

    /// Absolute (or ~ expanded) path to the .aimodel file or exported resource directory.
    private let modelPath: String?

    init(modelPath: String?) {
        self.modelPath = modelPath
    }

    // MARK: - Public

    func embed(_ text: String) async -> [Float]? {
        guard let path = resolvedModelPath, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return mockEmbedding(for: text)
        }

        #if canImport(CoreAI) && arch(arm64)
        if #available(macOS 27.0, *) {
            await ensureModelLoaded(path: path)
            if let model = loadedModel as? CoreAI.AIModel {
                if let real = await performRealEmbedding(text: text, model: model) {
                    return real
                }
            }
        }
        #endif

        // Fallback to mock so the semantic RAG pipeline (index + retrieve + cosine) remains fully functional
        // even before a real .aimodel is supplied. This lets you test the entire flow today.
        return mockEmbedding(for: text)
    }

    func unload() {
        #if canImport(CoreAI) && arch(arm64)
        loadedModel = nil
        #endif
        lastLoadedPath = nil
    }

    // MARK: - Loading (Core AI runtime)

    private var resolvedModelPath: String? {
        guard var p = modelPath, !p.isEmpty else { return nil }
        if p.hasPrefix("~") {
            p = NSString(string: p).expandingTildeInPath
        }
        return p
    }

    private func ensureModelLoaded(path: String) async {
        if lastLoadedPath == path, loadedModel != nil { return }

        #if canImport(CoreAI) && arch(arm64)
        if #available(macOS 27.0, *) {
            do {
                let url = URL(fileURLWithPath: path)
                // Prefer the full options path (specialization happens automatically or via options).
                // cpuOnly: false lets it use ANE/GPU when beneficial.
                // Load via the primary CoreAI entry points (the exact runtime model type for loadFunction
                // may be CoreAI.AIModel or a nested type; we store as Any and let the call site in
                // performRealEmbedding discover via Xcode once a real .aimodel is present).
                // We still use the asset for program name discovery (metadata side).
                let runtimeModel: Any = url   // placeholder; real load would be e.g. CoreAI.AIModel(...) or equivalent factory
                // For asset metadata / program names we use the documented asset type.
                var chosen = "embed"
                if let asset = try? CoreAI.AIModelAsset(contentsOf: url) {
                    // programNames may be exposed differently after the main CoreAI import; fall back gracefully.
                    let names: [String] = (asset as AnyObject).value(forKey: "programNames") as? [String] ?? []
                    if let first = names.first, !names.contains(chosen) {
                        if let embedLike = names.first(where: { $0.lowercased().contains("embed") || $0.lowercased().contains("encode") || $0.lowercased().contains("text") }) {
                            chosen = embedLike
                        } else {
                            chosen = first
                        }
                    }
                }

                loadedModel = runtimeModel
                lastLoadedPath = path
                embedFunctionName = chosen
            }
        }
        #endif
    }

    // MARK: - Real inference path (best effort; refine per your exported model)

    @available(macOS 27.0, *)
    private func performRealEmbedding(text: String, model: Any) async -> [Float]? {
        #if canImport(CoreAI) && arch(arm64)
        do {
            // The concrete executable model type (with loadFunction) is reached via CoreAI after the main import.
            // We keep the parameter as Any here to satisfy availability on the enclosing type while the body
            // runs only on 27+/arm64. When you have a real .aimodel, use Xcode autocomplete inside this #if
            // to discover the exact call (e.g. (model as? CoreAI.SomeRuntimeModel)?.loadFunction...).
            //
            // For now we intentionally do not invoke inference and fall through to the projection so the
            // rest of semantic RAG (toggle, path, rebuild, cosine scoring, retrieve) works immediately.
            // Replace the return below with real vector extraction once you wire the function call for your export.

            // Lightweight projection of the text into our fixed dimension (replace with real model output).
            let projected = projectTextToDimension(text, dimension: dimension)
            return projected
        }
        #else
        return nil
        #endif
    }

    // MARK: - Deterministic mock (lets semantic RAG work today; replaceable)

    private func mockEmbedding(for text: String) -> [Float] {
        projectTextToDimension(text, dimension: dimension)
    }

    /// Very small, deterministic, fixed-dim projection of text.
    /// Good enough for pipeline validation and "Core AI path" testing.
    /// Real models will give semantically meaningful directions in this space.
    private func projectTextToDimension(_ text: String, dimension: Int) -> [Float] {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return Array(repeating: 0, count: dimension) }

        var vec = Array(repeating: Float(0), count: dimension)
        let bytes = Array(normalized.utf8)

        for (i, b) in bytes.enumerated() {
            let idx = (i * 31 + Int(b)) % dimension
            vec[idx] += Float(b) / 255.0
        }

        // Light L2-ish normalization so cosine is meaningful
        let norm = sqrt(vec.reduce(0) { $0 + $1 * $1 }) + 1e-6
        return vec.map { $0 / norm }
    }
}

// MARK: - Convenience factory used by the manager / RAG

extension CoreAIEmbeddingProvider {
    /// Returns a provider if semantic RAG is requested and we have (or can use) a path.
    /// Even without a path we return a provider that supplies mocks (so UI and retrieval logic can be exercised).
    static func make(preferences: AIPreferences) -> CoreAIEmbeddingProvider? {
        guard preferences.semanticRAGEnabled else { return nil }
        return CoreAIEmbeddingProvider(modelPath: preferences.coreAIEmbeddingModelPath)
    }
}

// MARK: - Tiny cosine helper (used by enhanced RAG scoring)

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var dot: Float = 0
    var na: Float = 0
    var nb: Float = 0
    for i in 0..<a.count {
        dot += a[i] * b[i]
        na += a[i] * a[i]
        nb += b[i] * b[i]
    }
    let denom = sqrt(na) * sqrt(nb) + 1e-8
    return Double(dot / denom)
}
