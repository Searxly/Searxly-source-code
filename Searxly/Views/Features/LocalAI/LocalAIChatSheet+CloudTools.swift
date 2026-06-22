//
//  LocalAIChatSheet+CloudTools.swift
//  Searxly
//
//  Cloud (Searxly AI) agentic turn: real OpenAI-style tool calling on the 70B.
//
//  This is the cloud counterpart to the Apple FoundationModels tools path in +Messaging.swift.
//  The cloud model can call web_search (private SearXNG → grounded answer) and open_website
//  (explicit navigation). web_search results are numbered so the model can cite them with [n],
//  and those sources are attached to the assistant message as clickable citation chips.
//

import Foundation
import SwiftUI

extension LocalAIChatSheet {

    /// Runs one cloud agentic turn and renders the grounded, cited answer.
    @MainActor
    func runCloudAgenticTurn(effectivePrompt: String, systemPrompt: String, thinkingId: UUID) async {
        LocalIntelligenceManager.shared.logAction(.chatTurn, summary: "Entering cloud tools path", detail: "promptLen=\(effectivePrompt.count)", usedModel: true)

        let box = CloudSourceBox()
        let tools = makeCloudTools(sourceBox: box)

        // Cloud-only instruction: encourage grounded search + bracket-number citations the user can click.
        let citationRule = """


        GROUNDED ANSWERS WITH CITATIONS — you have a private web_search tool (uses ONLY the user's own SearXNG):
        - For factual, current-events, people, company, product, or "what/who/latest" questions, call web_search.
        - Read the returned results, then write a direct, natural answer in your own words.
        - Cite the specific results you used with their bracket numbers EXACTLY as shown, e.g. [1], [2], placed right after the sentence they support. Only cite numbers that actually appear in the results; never invent sources or URLs.
        - Use open_website ONLY for an explicit navigation request ("open …", "go to …").
        """
        let systemWithCitations = systemPrompt + citationRule

        do {
            let result = try await conversationEngine.generateCloudWithTools(
                prompt: effectivePrompt,
                instructions: systemWithCitations,
                tools: tools
            )

            LocalIntelligenceManager.shared.logAction(
                .chatTurn,
                summary: "Cloud tools turn returned",
                detail: "replyLen=\(result.text.count), tools=\(result.toolsUsed.joined(separator: ",")), sources=\(result.sources.count)",
                usedModel: true
            )

            // Replace the thinking placeholder with the final answer (+ sources for citation chips).
            if let idx = messages.lastIndex(where: { $0.id == thinkingId }) {
                messages.remove(at: idx)
            }
            let finalText = result.text.isEmpty ? "I didn't get a response. Try rephrasing." : result.text
            let sources = result.sources.isEmpty ? nil : result.sources
            messages.append(ChatMessage(role: .assistant, text: finalText, sources: sources))
            currentFollowUpSuggestions = []
            isThinking = false
            syncCurrentConversation()

            // Cheap follow-up suggestions (routed on-device via auxiliaryProvider — never bills the cloud).
            if !manager.preferences.lowMemoryMode {
                Task {
                    do {
                        let recent = buildTinyContextForSuggestions()
                        let suggs = try await conversationEngine.suggestFollowUpPrompts(
                            recentContext: recent,
                            lastAssistantResponse: finalText
                        )
                        await MainActor.run { currentFollowUpSuggestions = suggs }
                    } catch { /* nice-to-have; ignore */ }
                }
            }
        } catch {
            LocalIntelligenceManager.shared.logAction(.error, summary: "Cloud tools turn failed", detail: "\(error)", usedModel: true)
            if let idx = messages.lastIndex(where: { $0.id == thinkingId }) {
                messages.remove(at: idx)
            }
            // error.localizedDescription is already sanitized by CloudIntelligenceProvider (brand-safe).
            let msg = (error as NSError).localizedDescription
            messages.append(ChatMessage(role: .assistant, text: msg.isEmpty ? "Searxly AI couldn’t complete that request. Please try again." : msg))
            safelyResetAIState()
        }
    }

    /// Builds the two cloud work tools bound to the same private closures the Apple path uses.
    func makeCloudTools(sourceBox box: CloudSourceBox) -> [CloudTool] {
        let ps = self.performPrivateSearch
        let ow = self.openWebsite

        let webSearch = CloudTool(
            name: "web_search",
            description: "Search the web using ONLY the user's own private/local SearXNG instance(s). Use for almost any informational, factual, knowledge, current-events, people, company, or 'what/who/latest' question. You receive numbered results ([1], [2], …) with titles, URLs and snippets — synthesize a direct natural answer and cite the ones you use with their bracket numbers. NEVER use for explicit navigation ('open the official site', 'go to x.com') — use open_website for those.",
            parameters: [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "The search query to send to the user's private SearXNG. Use the user's words, refined slightly for better results."
                    ]
                ],
                "required": ["query"]
            ],
            execute: { @Sendable args async -> CloudToolOutput in
                let q = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let searcher = ps, !q.isEmpty else {
                    return CloudToolOutput(modelText: "No private search is available right now.")
                }

                // Best-effort: make sure the user's local SearXNG is up (no-op for remote-only setups).
                DispatchQueue.main.async {
                    Task {
                        let mgr = LocalSearxngManager.shared
                        if mgr.projectFolderExists {
                            if await mgr.isLocalWebReady() {
                                await mgr.refreshStatus()
                            } else {
                                await mgr.ensureReadyAndRunning()
                            }
                        }
                    }
                }
                let isRunning = await MainActor.run { LocalSearxngManager.shared.status == .running }
                try? await Task.sleep(for: .milliseconds(isRunning ? 180 : 650))

                let results = await searcher(q)
                guard !results.isEmpty else {
                    return CloudToolOutput(modelText: "No results from the user's private SearXNG instance(s) for \"\(q)\".")
                }

                let start = box.sources.count
                var lines: [String] = ["Private search results for \"\(q)\":"]
                for r in results.prefix(6) {
                    let id = box.add(title: r.title, url: r.url, engine: r.engine)
                    let snip = (r.content ?? "").prefix(240)
                    lines.append("[\(id)] \(r.title)\nURL: \(r.url)\nSnippet: \(snip)")
                }
                let mine = Array(box.sources[start...])
                return CloudToolOutput(modelText: lines.joined(separator: "\n\n"), sources: mine)
            }
        )

        let openWebsiteTool = CloudTool(
            name: "open_website",
            description: "Open a website in the user's browser as a new tab. Use ONLY for explicit navigation commands ('open the official Tesla site', 'go to x.com', 'visit the Wikipedia page'). Pass a clean entity name or domain; the host resolves it privately. NEVER use for informational questions — those are web_search cases.",
            parameters: [
                "type": "object",
                "properties": [
                    "description": [
                        "type": "string",
                        "description": "Clean site name or domain to open (e.g. 'Tesla', 'x.com', 'Apple developer'). For the platform formerly known as Twitter always use 'x.com'."
                    ]
                ],
                "required": ["description"]
            ],
            execute: { @Sendable args async -> CloudToolOutput in
                let desc = (args["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let opener = ow, !desc.isEmpty else {
                    return CloudToolOutput(modelText: "Opening websites isn't available right now.")
                }
                await MainActor.run { opener(desc) }
                return CloudToolOutput(modelText: "Opened \"\(desc)\" in a new tab (resolved privately via the user's SearXNG).")
            }
        )

        return [webSearch, openWebsiteTool]
    }
}
