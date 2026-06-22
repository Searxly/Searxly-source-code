//
//  CloudTool.swift
//  Searxly
//
//  Provider-agnostic tool description for the cloud (OpenAI-compatible) tool-calling path.
//
//  The Apple on-device path uses FoundationModels' `Tool` protocol (`@Generable`, Apple-only). The
//  cloud 70B can't use those types, so this describes a tool in plain OpenAI function-calling JSON
//  plus an async executor. CloudIntelligenceProvider.generateWithTools(...) runs the agentic loop
//  with these — letting the big model reliably call web_search / open_website and produce grounded,
//  cited answers in the chat.
//

import Foundation

/// A tool the cloud model can call, described in OpenAI function-calling form.
struct CloudTool {
    let name: String
    let description: String
    /// JSON Schema object for the function parameters (the OpenAI `parameters` field).
    let parameters: [String: Any]
    /// Runs the tool with decoded arguments. Returns the text the model will see next, plus any
    /// user-facing sources to surface (e.g. the private search results behind a grounded answer).
    let execute: @Sendable ([String: Any]) async -> CloudToolOutput
}

/// What a single CloudTool run produces.
struct CloudToolOutput {
    /// Text fed back to the model as the tool result (the model reasons over this).
    let modelText: String
    /// Sources to attach to the assistant message for the user (clickable citations). Usually empty
    /// for side-effect tools (open_website) and populated for web_search.
    var sources: [Citation] = []
}

/// Final result of a complete cloud tool-calling turn.
struct CloudToolResult {
    /// The model's final natural-language answer (after any tool results were incorporated).
    let text: String
    /// De-duplicated sources gathered across every tool call in the turn, in citation order.
    let sources: [Citation]
    /// Names of tools the model actually invoked this turn (for logging / UX, e.g. dismiss on open_website).
    let toolsUsed: [String]
}

/// Thread-confined running accumulator used to assign stable, turn-wide citation numbers across
/// multiple web_search calls. The tool-calling loop awaits each call sequentially, so no locking is
/// needed; `@unchecked Sendable` lets it cross the `@Sendable` executor boundary.
nonisolated final class CloudSourceBox: @unchecked Sendable {
    private(set) var sources: [Citation] = []

    /// The next 1-based citation index (continues across calls within a turn).
    var nextIndex: Int { sources.count + 1 }

    /// Append one source and return the citation number assigned to it.
    @discardableResult
    func add(title: String, url: String, engine: String?) -> Int {
        let id = nextIndex
        sources.append(Citation(id: id, title: title, url: url, engine: engine))
        return id
    }
}
