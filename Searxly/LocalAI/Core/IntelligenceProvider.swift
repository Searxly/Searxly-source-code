//
//  IntelligenceProvider.swift
//  Searxly
//
//  NEW FILE (Phase 0).
//  Protocol abstraction so the rest of the app (manager, engines) does not
//  directly depend on FoundationModels, Ollama, or future MLX.
//  Primary implementation = AppleIntelligenceProvider (Phase 0/1).
//  Experimental fallbacks are explicitly gated in the manager.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Capability a provider must declare so the manager can decide routing and UI messaging.
struct ProviderCapabilities: Equatable {
    let supportsStreaming: Bool
    let maxContextTokensApprox: Int
    let name: String          // "Apple Intelligence", "Ollama (local)", etc.
    let supportsNativeTools: Bool   // WWDC26+ native Tool / Generable support for reliable agentic calling
}

/// The minimal contract used by QueryRewriter, ResultSynthesizer, ConversationEngine, etc.
protocol IntelligenceProvider {
    var capabilities: ProviderCapabilities { get }

    /// One-shot generation (most common for rewrite + synthesis). No tools.
    func generate(prompt: String, instructions: String?) async throws -> String

    /// Optional streaming for chat (implementations may fall back to non-streaming).
    func generateStream(prompt: String, instructions: String?) -> AsyncThrowingStream<String, Error>

    /// Best-effort unload / release heavy resources (session, loaded weights, etc.).
    func unload() async

    #if canImport(FoundationModels)
    /// Native tool calling generation (when toolsEnabled and provider supports it).
    /// The provider creates a LanguageModelSession with the provided tools (for schema + execution).
    /// When the model chooses tools, the Tool.call implementations (bound to real private actions)
    /// are invoked by the framework during respond. The returned content is the final natural response
    /// (after any tool results were incorporated by the model). Confirmation / auto-execute is controlled
    /// by the caller (see toolsEnabled toggle and LocalAIChatSheet).
    /// NOTE: [any Tool] and the Tool protocol itself only exist when FoundationModels is importable.
    func generate(prompt: String, instructions: String?, tools: [any Tool]?) async throws -> String
    #endif
}

extension IntelligenceProvider {
    // Default non-streaming implementation for providers that don't support it.
    func generateStream(prompt: String, instructions: String?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let full = try await generate(prompt: prompt, instructions: instructions)
                    continuation.yield(full)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    #if canImport(FoundationModels)
    /// Default: fall back to plain generate (no native tools). Concrete providers (Apple) override for real support.
    func generate(prompt: String, instructions: String?, tools: [any Tool]?) async throws -> String {
        return try await generate(prompt: prompt, instructions: instructions)
    }
    #endif
}