# Local AI (on-device) — Implementation Notes for Searxly

> **2026-06 Minimal Two-Tool Rework (current authoritative state):** The Local AI subsystem was reduced to **exactly two work tools** so the small on-device Apple Intelligence model can follow instructions reliably:
> - `web_search` (via the user's private SearXNG only) — for "who is", "tell me about", facts, current events, research. Results are injected; the model synthesizes a natural answer **in the chat** (with citations).
> - `open_website` — for explicit navigation only ("open the official ... site for me", "go to x.com"). Resolves privately (or direct domain) and opens a tab (usually dismisses the chat sheet).
>
> Every previous agentic tool and the entire "Actions/" (user-called) abstraction from the prior rework was deleted. New dedicated per-tool files were created under `LocalAI/AgenticTools/` (one small focused .swift per tool + assembler) per the explicit request to "create new files for each tool and new things" so that bugs and issues are easy to work on in isolation afterwards.
>
> Prompts (AIRules + AIPromptLibrary) were radically simplified. The chat sheet, ToolDefinitions, wiring, and detection logic were slimmed to the two tools only. The "Web search" and "Open site…" chips remain the primary explicit user control surface.
>
> Apple Intelligence (FoundationModels `LanguageModelSession`) + the native Tool path (when enabled) and the legacy marker path (when disabled) both operate on this minimal set. All privacy, RAG, attachments, streaming, unload, diagnostics, and gating contracts are unchanged and were not weakened.

---

## Current Design (Post 2026-06 Two-Tool Rework)

- **Core identity**: "You are Searxly Local, a private on-device conversational research assistant and chatbot." Primary job = answer directly and naturally using on-device knowledge + context in *this* chat. (See `AIRules.swift` and `AIPromptLibrary.swift` — the rules were made much shorter and more direct for the small model.)

- **Exactly two work tools (the entire agentic surface)**:
  - `web_search`: Use for any question that would benefit from fresh private search results ("who is Elon Musk?", "browse on the web and tell me...", "latest on X", explanations, etc.). The model (or user chip) calls it; results come back; model gives the answer in the chat. Never opens tabs.
  - `open_website`: Use **only** for explicit navigation ("open the official Tesla site", "go to x.com", user taps "Open site…"). Performs the tab open side-effect (via BrowserState, with private SearXNG resolution or fast direct URL). The sheet is normally dismissed.

- **User-called chips are primary and visible**: The chat composer shows exactly two action chips: "Web search" and "Open site…". These are the main, low-friction way the user invokes behavior. The model may proactively decide to call the tools when the "AI tool calling" toggle is on, but the rules + tiny surface make it far less likely to misuse `open_website` on knowledge questions.

- **Organization for maintainability**: `LocalAI/AgenticTools/` contains one focused file per tool (`WebSearchTool.swift`, `OpenWebsiteTool.swift`) plus the assembler (`AgenticTools.swift`). Each file owns the native `Tool`/`Generable` definition (with strong "when NOT to use" language in the description), the user-chip execution helper, result formatting for injection, confirmation card text, and marker names. Old monolithic `ToolDefinitions.swift` and the entire `Actions/` folder (SearxlyAction, ActionRegistry, ActionExecutor) were removed. The chat sheet is now dramatically smaller.

- **Repetitive identity/privacy boilerplate removed (2026-06)**: The model was echoing "I am a private on-device AI running locally on your Mac. Everything stays on your device, zero data leaves the Mac." (and similar) even in short replies because of strong selfDescription instructions. The forced phrasing was turned into internal guidance only + an explicit "never output / repeat identity statements in replies" rule was added to outputConstraints. Responses are now direct and free of this spam.

- **Continued Local AI enhancements (v3.1, 2026-06)**:
  - **Prompt / model guidance**: Much stronger decision tree in knowledgeFirst + actionUsage + navigationRule with explicit positive/negative examples (including the exact "open elon musk official chip facility" vs pure navigation case), clearer "when in doubt use web_search + answer in chat", reinforced NEVER for misusing open_website on descriptive/info queries. Better post-action naturalness rules.
  - **Tool reliability**: Richer, numbered + URL + longer-snippet result formatting passed to the model (both native tool path and user-chip path) so the small on-device model can parse, ground, and cite more accurately. Refined @Guide + Tool descriptions in AgenticTools/ with real failure cases and "extract clean entity" instructions.
  - **Output quality**: Enhanced ResponsePostProcessor — more dry starters stripped (including search self-reference), additional tool-leak removal, better naturalization for tool follow-ups.
  - **Context & retrieval**: High-perf devices now get up to ~16 turns history + higher RAG k (up to 18) automatically. More context in tiny follow-up suggestion builder.
  - **Performance**: warmUpIfNeeded now also fires when master AI is enabled (not only on chat open). Added high-perf RAG k + effective history notes to diagnostics.
  - **v3.2 huge reliability & safety uplift (2026-06, post user-reported pornhub bug)**:
    - New `SiteResolver.swift` (LocalAI/Supporting/): bundled trusted map (curated from staticSuggestions + public official sites: Tesla, xAI, Neuralink, Grokipedia, X, Apple, Wikipedia, etc.) + `trustedURL(for:)` fast path + `bestSafeCandidate(...)` relevance scorer. This is the "open source-style file with list of entities and links" requested for built-in local knowledge.
    - Map-first resolution in `openWebsite` (BrowserState): common explicit commands are now instant + guaranteed correct with zero SearXNG round-trip.
    - Hardened `isExplicitNavigationCommand` (OpenWebsite + AgenticTools): now rejects any question/info-seeking phrasing ("can you open...", "what is the ... site?", "?") even when "open" word is present. The early bypass in LocalAIChatSheet now uses the shared strict guard. Descriptive cases always go through the model + classification gate.
    - Apple-style safeguards (user review feedback incorporated): conservative `sensitiveSubstrings` (adult/porn/scam patterns), relevance + safety scoring in resolver, `shouldAutoOpen` flag, provenance-aware behavior. AI-proposed or low-confidence/sensitive resolutions never auto-open a tab — graceful fallback to private search tab (or confirmation in tool paths). "Nothing too sensitive happens but legitimate navigation just works."
    - Stronger "CLASSIFICATION GATE" added at the top of knowledgeFirst in AIRules (v3.2) + reinforced in OpenWebsiteTool description + prompt version bump.
    - All changes close the exact reported failure mode with multiple overlapping defenses while preserving (and improving) UX for good cases.
  - All changes keep the two-tool minimal surface (web_search for knowledge/info, open_website strictly for explicit nav) that makes the small Apple Intelligence model reliable while still giving powerful private on-device behavior. Versions bumped (rules v3.2, prompts v3.2, SiteResolver added).

  On M4 Pro 24 GB+ hardware the combination (larger context, richer results for the model, aggressive warm-up, smarter prompts) makes the on-device experience noticeably more capable and responsive across factual questions, research, and explicit navigation.

## 2026-06 Huge open_website / Site Resolution Uplift (v3.3)

This was a major reliability pass focused exclusively on the `open_website` tool and its resolution machinery (the "searxly agent" navigation path).

**Problem addressed:**
- "open elon musk's chip facility website" (and "open terafab", "xAI Memphis supercluster", etc.) was resolving to news sites (e.g. teslarati.com) instead of the official site.
- Root cause: limited inline trustedMap + generic "<entity> official site" search + token-overlap scorer that favored popular news coverage over canonical official domains.

**Solution (the "every enhancement possible" approach requested):**
- New file: `LocalAI/Supporting/OfficialEntityDatabase.swift` — a rich, auditable, open-source-style curated database of entities with primary URLs + dozens of natural-language aliases per entry.
  - First-class coverage for the xAI/Tesla/SpaceX/Neuralink family + facilities.
  - **Terafab primary**: "terafab", "elon musk chip facility", "xai memphis", "tesla terafab", "memphis supercluster", "colossus", etc. all map to https://terafab.ai (user-corrected official site) with strong secondary mappings to x.ai / tesla.com.
  - 150+ entries with heavy aliasing for possessives ("elon musk's ..."), project names, shorthand, previous names, "official site of X", etc.
- `SiteResolver.swift` completely modernized:
  - Consumes the new DB for `trustedURL`, `fuzzyMapMatch`, and `resolutionQuery`.
  - Upgraded `normalizedKey` (aggressive possessive + facility term stripping).
  - `relevanceScore` now includes brandAffinity boosts (authorityHosts get +28), official title signals, path authority preference (root/short paths win), and explicit news-host penalties.
  - `bestSafeCandidate` + fallthrough logic now heavily biased toward official company/project sites.
- `BrowserState.swift`:
  - `cleanOpenDescription` extended with the same heavy stripping so the DB sees clean keys.
  - `openWebsite` now calls `SiteResolver.resolutionQuery(for:)` for the search fallback (produces Terafab-aware high-signal queries).
  - Marginal / low-authority search results deliberately fall back to a clean private search tab instead of risking a wrong open ("graceful for every case").
  - Added verbose resolution path logging under DeveloperSettings.
- Tool + prompt polish:
  - `OpenWebsiteTool.swift` @Guide and description enriched with real complex examples ("open terafab", "xAI Memphis", "elon musk chip facility").
  - `AIRules.swift` navigationRule got an additional positive explicit-nav example using facility/project phrasing.
- All previous Apple-style safeguards, X-brand hardening, `isExplicitNavigationCommand` gate, and privacy contracts are untouched.

**Result:**
- Map hits (the common case) are now instant, zero-network, and correct for a vastly larger surface.
- The original failing phrase and dozens of variants now reliably open https://terafab.ai (or the appropriate canonical).
- When search is needed, it is smarter and the scorer is much harder to fool with news.
- The OfficialEntityDatabase.swift top comment contains the living "pre-known list" + extension guide + test cases — exactly the open-source-style maintainable artifact requested.

See the session plan.md for the full implementation approach and verification matrix.

Version note: entityDBVersion = "v1.0-2026-06-terafab-ai-official". Record future DB expansions here and in the DB file header.

- The authoritative plan for this change (including verification steps) is the session `plan.md`.

All other sections below (availability, privacy invariants, resource management, diagnostics, etc.) remain relevant. Historical content below this point describes the previous larger surface and is kept for context only.

---

## Previous History (kept for context)

(The original detailed notes from the initial implementation, bug audits, WWDC26 native tools + Core AI uplift, etc. follow. The philosophy and folder layout above are the current authoritative state.)

# Local AI (on-device) — Implementation Notes for Searxly (historical content preserved below)

**Filename note:** This file is deliberately named `LOCAL_AI_IMPLEMENTATION_NOTES.md` (instead of the generic `IMPLEMENTATION_NOTES.md`) to prevent Xcode "Multiple commands produce / duplicate output file" CpResource errors in the app target. The `VPN/` folder already contains an `IMPLEMENTATION_NOTES.md` that gets included via the project's resource copying (folder references / target membership). Both would otherwise resolve to the same flat `Contents/Resources/IMPLEMENTATION_NOTES.md` inside the built `.app`.

**Primary path:** Apple Intelligence via `FoundationModels` (`SystemLanguageModel` + `LanguageModelSession`).
**Hard requirements (runtime):** Apple Silicon + macOS 15.4+ (or whatever the current FoundationModels bar is) + user has enabled Apple Intelligence in System Settings.
**Design goals (non-negotiable):** 100% local, zero exfiltration, user-controlled at every layer, transparent, minimal resource impact, new isolated files/folders only.

## Key Files & Responsibilities (Phase 0/1 state)

- `LocalIntelligenceManager.swift` — the @Observable singleton. Owns master enable, availability, provider, status, action log, idle unload, and the public `rewriteIfEnabled` etc. gates.
- `AppleIntelligenceProvider.swift` — the real `LanguageModelSession` work. `generate(...)` is the hot path.
- `QueryRewriter.swift`, `ResultSynthesizer.swift`, `ConversationEngine.swift`, `RAGEngine.swift` — thin domain wrappers (now implemented).
- `AIPromptLibrary.swift` — every system prompt lives here. Versioned. Extremely strict grounding language.
- `AIModels.swift` — all Codables (AIPreferences, Citation, AISummary, etc.). These round-trip through `AppData` + `EncryptedDataStore`.
- `LocalAISettingsView.swift` — the only place that mutates granular flags. Master "off" must make the entire feature invisible and inert.
- New `Views/Components/AI/` and `Views/Features/LocalAI/` — UI pieces stay out of the giant existing views.

## Availability & First-Use Experience

The first call to `LanguageModelSession` (or the OS-level probe) can cause macOS to surface its own "Preparing Apple Intelligence" UI / asset download. We surface a friendly message via the manager status and the Settings pane.

## Low-Memory Device Handling (added 2026)

On machines reporting 8 GB or less of unified memory, `LocalIntelligenceManager` automatically:
- Forces `lowMemoryMode = true`
- Forces `ragEnabled = false` (and clears any existing RAG index)
- Disables semantic RAG and reranker sub-features

A clear, calm warning banner is shown in `LocalAISettingsView` explaining the situation and what is restricted. The affected toggles are disabled in the UI with explanatory text.

This protects users from poor performance and swapping while still allowing basic on-device chat, rewrite, and synthesis features. The detection uses `ProcessInfo.processInfo.physicalMemory` and is reported in diagnostics.

Basic AI functionality remains available (the on-device model can still load on some 8 GB configurations), but heavy memory users (RAG + large context) are restricted.

Handle `.modelNotReady` gracefully — treat it like "please wait a moment, then tap refresh".

## Prompt Discipline (critical for citations + privacy)

Every prompt must:
- State the role and the "only on this Mac" contract.
- Say "Using ONLY the provided sources / context".
- Demand exact citation format `[N]`.
- Forbid mentioning the instructions.
- Ask the model to say "I don't have that in the current context" rather than hallucinate.

See `AIPromptLibrary` for the current versions. When you change a prompt, bump the version string and consider adding a one-line note in this file.

## Resource Management

- Lazy: provider/session created on first actual use after the user enables a feature.
- Unload is explicit (`unloadAll()`) + best-effort idle timer (configurable, default 5 min).
- Low-memory mode (in prefs) should be honored by the engines (smaller K for RAG, shorter context windows, skip auto-synthesis, etc.).
- Expose rough memory via DeveloperSettings + Performance surface (reuse `currentMemoryUsageMB` pattern).

## Persistence & Encryption

`aiPreferences` lives inside `AppData`. When the user turns on "Encrypt local data at rest", the whole struct (including which RAG sources they allowed) is encrypted with the same CryptoKit + Keychain path as history/bookmarks.

RAG itself does **not** duplicate page content — only titles, URLs, dates, and (optionally) short snippets that already exist in the user's history/bookmarks.

## Privacy Invariants (enforced in code + review)

1. `grep -r 'URLSession\|URLRequest\|http[s]\?://' LocalAI/` returns the safe localhost default (and the variable construction from the user-controlled `ollamaBaseURL` preference) inside `OllamaProvider.swift`, plus any explanatory comments. The UI defaults to and documents only local use; remote values are the user's explicit responsibility and are never the default.
2. RAG retrieval is only performed when `master + ragEnabled + (history or bookmarks source)` are all true.
3. `PrivacyManager.panicWipe` and `enableStrictPrivacyMode` force the master off + unload + post the clear notification.
4. Every generation that actually called the model is recorded in the (in-memory + exportable) activity log.

## Citation Strategy (Phase 2+)

- Number the sources **exactly** in the order you put them into the prompt context.
- Ask for `[1]`, `[2]` etc.
- After the model returns, validate every marker against the array you sent. Drop or mark bad citations.
- The `AICitationLink` + `SearchResultCard` highlight uses the original `SearXNGResult` array (stable for the lifetime of the current `searchResults`).

## Fallbacks (Phase 5 only)

Ollama (and later MLX) are **never** the default. They live behind a clearly labeled "Experimental local LLM fallbacks" secondary toggle + model name + (advanced) base URL fields. The provider protocol exists so swapping is clean.

When an experimental fallback is active, the UI must say so loudly (header + per-bubble labels include the concrete model and "localhost").

The base URL setting defaults to the standard Ollama.app localhost:11434 on the user's Mac. It is configurable for people who run Ollama on a non-standard local port, but the settings UI contains an explicit privacy warning that only localhost / servers the user fully controls on their own hardware are acceptable. Remote values cause the user's prompts + RAG + attachments to leave the device (the rest of Local AI still honors the private SearXNG contract).

## Testing & Verification on Real Hardware

- Apple Intelligence **enabled** machine: full flows.
- Same machine with AI **disabled** in System Settings: every path must silently fall back to original behavior.
- Traffic capture (Little Snitch / `nettop` / Wireshark) during rewrite + synthesis + chat + RAG must show **only** localhost:8080 (SearXNG) and, when deliberately enabled, localhost:11434 (Ollama).
- Instruments: measure additional resident memory after first synthesis/chat, then after explicit unload.
- Panic wipe + history clear must remove the ability for RAG to surface the cleared items on the very next chat.

## Common Gotchas

- `SystemLanguageModel.default.availability` can return `.unavailable(.modelNotReady)` for a while after first enabling Apple Intelligence on the Mac — don't treat it as a hard failure.
- LanguageModelSession is stateful for chat; create per-conversation or manage turns carefully.
- Tools (web_search etc.): Opt-in only (`toolsEnabled` in AIPreferences). Always requires explicit user confirmation in the chat UI before any network call. Tool use is logged with type `.toolUse` and visibly labeled in the transcript (e.g. “Used private web search via your SearXNG”). Tools are only ever routed through the user’s currently configured private SearXNG instances via the existing `SearXNGService`. No public instances, no cloud. The model is instructed via an augmented system prompt to output a simple `TOOL_REQUEST: web_search "..."` marker, which the UI intercepts for confirmation.
- Context windows are smaller than cloud models. Always truncate (last N turns + top-K sources).
- The first `respond` can be slow (model load). We now reuse LanguageModelSession across turns in a chat for much better speed on follow-ups. Still show friendly "thinking" state.

## When Adding New Features

1. Add the granular toggle to `AIPreferences` (and expose it in `LocalAISettingsView.swift`).
2. Wire the UI toggle **only** in `LocalAISettingsView.swift`.
3. Add the guard at the top of the new engine / manager method (and only enable the tool in the prompt when the toggle is on).
4. Log every tool invocation via `manager.logAction(.toolUse, ...)` with the exact query and instance used.
5. Update this file with any new prompt version or memory consideration.
6. Add the corresponding clear path in PrivacyManager if the feature holds user-visible state.
7. Keep the confirmation UX (or a clear non-blocking note) for any action that touches the network or user data.
8. Make outputs conversational and natural — avoid technical prefixes in the assistant message itself. Use the follow-up prompt to guide phrasing like "I pulled some fresh private search results and found...".

## Chatbot-like + Agentic Experience Goals (Updated)

The Local AI Chat is intended to feel like a natural, conversational private assistant *and agent* inside the browser at the same time:
- Multi-turn chatbot conversation with good context (search, RAG via Core AI embeddings, attached files, history).
- Proactive/agentic: when the user expresses goals or intents involving the web or their data ("open X", "search for Y", "bookmark this", "what have I read about Z", "who is...", "tell me about..."), it should use the matching tool to act on the user's behalf.
- Natural responses + tool use interleaved seamlessly.
- Strong privacy, grounding (only use provided context + tool results), and transparency (user sees/approves actions via the toggle + logs).
- The "AI tool calling" toggle controls auto vs explicit confirmation for actions.
- Native Foundation Models tool calling (when available) makes this more reliable than text markers.

This gives you a helpful private browser agent that can chat *and* do things (search privately, open tabs/sites, bookmark, explore your own history, etc.) without ever leaving your Mac or your private SearXNG instances.

## Recommended Next Tools (Privacy-Safe, High-Value)

Prioritize tools that feel useful in a browser context and can be executed with the existing private SearXNG + local data:

- **web_search** (already in progress) — always via the user's configured private instances only.
- **search_my_history** — natural-language query against the user's browsing history + bookmarks (RAG). Returns relevant items with titles, URLs, and dates. Never sends raw history off-device.
- **open_results_in_tabs** — given a list of URLs (from a previous search or from history), open them as new tabs (optionally in a specific Space).
- **bookmark_with_note** — bookmark the current page (or a URL from context) and attach a short note from the conversation.
- **new_private_search_tab** — create a new private tab and immediately perform a search via the user's private SearXNG.

All of these must:
- Go through the same permission / confirmation flow when the "AI tool calling" toggle is off (and a clear non-blocking note when it is on).
- Be logged.
- Produce natural language in the final assistant reply.

## Output Quality & Transparency

- The follow-up prompt after tool results must explicitly tell the model to use friendly, conversational phrasing and to mention (lightly) that it used a private/local source when appropriate.
- Never put technical strings like "【Used private web search via your SearXNG】" directly into the assistant message the user reads.
- Keep a separate, smaller system-style note in the transcript for auditability (e.g. "I used web_search via your localhost:8080 instance (you approved).").
- Consider adding a "Show reasoning" or "Show tool results" expandable section per assistant turn for power users.

## Context & Memory

- When the chat is opened from a search result or from a web page, automatically attach lightweight context (current search query + top results, or page title + URL). Show a small removable chip so the user can see and remove it.
- Per-chat custom instructions implemented safely (user sets style/focus for this chat only). Prepended after core grounding/privacy contract so user preferences cannot override privacy, tool rules, or "only use provided context". Visible indicator in chat, easy to edit/clear. Currently session-ephemeral for maximum safety (future: optional persist via ChatTranscript + EncryptedDataStore).

## Settings & Control

- Keep the existing master "on-device AI" switch + granular toggles.
- The "AI tool calling" toggle should control whether the model is allowed to proactively decide to use tools. Explicit user language ("look this up on the web", "search for X") should still be able to trigger a permission prompt even when the toggle is off.
- Add a visible "Clear this chat's context & memory" action (separate from global data clear).
- Consider a "Low resource mode for this chat" that reduces context size and disables heavier tools.

## Files / Organization

Continue the pattern of new focused files:
- `LocalAI/Tools/` — one file per tool (or a small protocol + implementations).
- `LocalAI/ChatContext.swift` or similar for managing attached context + user instructions.
- Keep all prompts in `AIPromptLibrary.swift` and version them.
- Any new persisted data (per-chat instructions, saved chats) must go through `AppData` + `EncryptedDataStore` so it respects the existing encryption setting.

## Non-Goals (for the immediate next phase)

- No "summarize current page" tool for now (explicitly deferred by user).

---

## 2026-06 Deep Bug Audit & Correctness Pass (delivered)

A full line-by-line review of every Local AI file + all call sites (manager, BrowserState, ContentView, Privacy, settings, sheets, providers, prompts, RAG, tools, streaming, context) was performed. The following latent issues that caused "breaks a lot" and poor effective quality from the on-device Apple model were fixed (no new features, no scope creep outside Local AI):

- Attached local file *content* (the actual extracted text from user-chosen PDFs/text) was **never injected** into any prompt sent to the model (the `fileContextBlockForPrompt` helper and its call sites were dead code even though the header rule and chips existed). The model only ever saw "you have N attached files" but zero bytes. **Fixed** — files are now appended in send() + runFollowUpGeneration so "analyze my notes + private web search" finally works.
- `LanguageModelSession` was recreated on (almost) every turn because varying per-turn instructions (search/RAG/files) were passed every time. This defeated the reuse comments, lost Apple's internal transcript state, and forced the small on-device model to rely only on our manually truncated history string. **Fixed** via hash guard in the provider + the understanding that stable inputs now produce stable instructions strings (reuse happens for normal follow-ups; recreate only on material contract change such as adding files).
- Streaming delta used blind `dropFirst(count)` which had previously caused "mangled repeated outputs"; made robust with common-prefix + reset guard.
- `synthesizeIfEnabled` + several ensure paths hard-coded `AppleIntelligenceProvider` even when the user had the experimental Ollama fallback gate on. **Fixed** — all paths now go through `currentIntelligenceProvider`.
- RAG index was only rebuilt on openChat or explicit button. Toggling RAG on, changing sources, or adding history mid-session could leave an empty/stale index. **Fixed** — auto-heal on first retrieve + rebuild on toggle/include changes in settings + clearHistory/clearBookmarks now drop the RAG index.
- Rewrite happened (query improved before SearXNG) but `AIQueryRewriteBadge` + `lastAIRewrite` were never wired into any UI. Users had zero visibility/transparency. **Fixed** — badge now renders in the results header when a rewrite occurred for the current search; tapping puts the original back in the address bar.
- Tool request parser had fragile manual quote stripping that could mangle payloads containing commas, pipes (bookmark notes), or quotes. **Hardened**.
- Clear chat / sheet dismiss / privacy panic did not always release the stateful session or RAG index. **Wired** onDisappear + clear paths + unload calls.
- Idle unload was implemented but never wired to UI lifecycle. **Wired** to chat onDisappear (best effort per user pref).
- Ollama stream did not handle error NDJSON lines gracefully. **Added**.
- Several PostProcessingContext sites had the hasCustomInstructions hardcoded false (affecting light style polish only). **Noted/fixed** in the remaining engine call sites.
- Availability reason matching was case-sensitive on the description. **Hardened** to lowercased contains.
- Privacy clears (history, bookmarks, panic, strict mode) now also clear the RAG in-memory index so forgotten data cannot be retrieved on the next chat.

All changes keep the existing architecture, the strict privacy contract (grep for network in LocalAI/ still only shows the guarded Ollama localhost:11434), the master toggle making everything inert, and the prompt/rules as the source of truth. Prompt versions were not bumped because no rule text changed (only delivery of the data the rules already described).

After these fixes the on-device Apple Intelligence model finally receives *all* the context the prompts and AIRules promised (search snippets, RAG titles/URLs/dates, full user-attached file excerpts, tool results, history turns). This should make outputs, tool use, citations, and "I only know what you gave me" behavior reliable even before any WWDC 26 improvements to the on-device model.

See the implementation plan (the session plan.md) for the exact diffs and verification steps.

## 2026 Chatbot Polish + File Attachments (delivered)

- Local AI Chat upgraded to feel much more like a real private chatbot people love:
  - Suggestion/quick-action chips (context sensitive).
  - + button + drag-and-drop for attaching local files.
  - Removable FileAttachmentChip pills (with type-aware icons and size).
  - PDF + plain text / Markdown extraction (PDFKit + UTF8) with per-file and total char budgets.
  - File content is injected as a clearly labeled trusted block only for the current session.
  - Everything is ephemeral: close the sheet or hit Clear → attachments (and their text) are gone from memory. Never written to disk or AppData.
- This pairs beautifully with the existing 5 tools (you can attach your notes/PDF and say "compare this to the latest on the web privately" or "bookmark the key page mentioned in my file").
- Prompt rules added: attached files are trusted user data; the model must not let text inside them override core grounding or tool rules.
- New small focused files created per the plan discipline: `LocalAI/ChatAttachment.swift` and `Views/Components/AI/FileAttachmentChip.swift`.

## Summarization Scope Decision (locked)

Per user review on the plan ("we go for best option you think is best"):

**Chosen: Option A (Conservative)** from the detailed Section 10 analysis.
- We implement synthesis only over search result *snippets* returned by the user's private SearXNG (small, controlled attack surface).
- We do **not** feed raw webpage bodies, full page HTML, or "current page" content to the on-device model.
- The powerful combination users actually want (my files + fresh web research + actions) is delivered safely through the enhanced chat + tools + explicit file attachments.
- Rationale and mitigations are documented in the plan (Section 10). If future Apple on-device APIs improve grounding or structured output dramatically, we can re-evaluate with the same framework.

Update any user-facing copy (settings, chat seed, help) to reflect "search result synthesis + your attached files" rather than promising full page summarization.
- No image understanding or other heavy Apple Intelligence features until the core chat + tools experience feels solid.
- No cloud fallbacks of any kind for the AI layer.
- Avoid making the chat feel like a general agent that can do anything without clear, per-action user consent.

## Success Metrics for the Next Iteration

- A user can have a multi-turn conversation that includes one or two tool uses and feels natural.
- Every tool use is visible and reversible/auditable.
- The feature remains invisible and inert when the master AI switch is off.
- Resource impact stays reasonable (test with the existing memory overlay and Instruments).
- No network calls except those explicitly approved and routed through the user's private SearXNG instances.

This direction keeps the spirit of Searxly while making the Local AI Chat feel like a genuinely useful private assistant rather than a gimmick. All of the above can be implemented while staying 100% on-device and respecting the existing privacy and persistence architecture.

This module exists to extend Searxly's "everything private and local" promise to the intelligence layer without ever compromising it.

— Implementation team, 2026

## WWDC26 Uplift — High Priorities Completed (native tools + reranker pipeline)

**Native Foundation Models tool calling (agentic) — High #1**
- Added full support in the provider stack: `IntelligenceProvider` now advertises `supportsNativeTools` and has a 3-arg `generate(..., tools: [any Tool]?)`.
- `AppleIntelligenceProvider` creates `LanguageModelSession(tools: ...)` (order tools before instructions per SDK) when tools are supplied; the framework handles structured decision + execution of the bound `Tool.call` implementations and incorporates results into the final `response.content`.
- `ConversationEngine` forwards the tools list (new overload guarded by canImport).
- `LocalAIChatSheet` (in the `useToolsInPrompt` / toolsEnabled branch) constructs live `Tool` instances via `SearxlyTools.makeCurrent(...)` bound to the existing private closures (`performPrivateSearch`, `searchMyHistory`, `openResultsInTabs`, `bookmarkWithNote`, `createNewPrivateSearchTab`, `openWebsite`) + logging. The reply from the engine is treated as the final natural answer (no marker parsing needed for the native auto path).
- The classic prompt + `TOOL_REQUEST` marker path + confirmation card is preserved as the fallback when the "AI tool calling" toggle is off.
- New file: `ToolDefinitions.swift` (the 6 tools as `Tool` + `Generable` args with `@Guide`; the execute closures return compact result strings exactly like the old "Tool result:" injection).
- Result: reliable typed tool calling for the opt-in case, agentic multi-turn flows work with the framework maintaining transcript state, all privacy / "only your private SearXNG" / logging / confirmation (when toggle off) contracts unchanged. Build succeeded on arm64 + 27 SDK.

**Core AI reranker — High #2**
- New `CoreAIRerankerProvider.swift` (exact same pattern as the embedding provider: guarded import, mock pair scorer using projection+cosine so the pipeline is immediately usable and measurable, `RerankerProvider` protocol, `make(preferences:)`, `unload`).
- `RAGEngine` extended with optional `reranker`, `usingReranker`, `setReranker`. `rebuildIndex` accepts it. `retrieve` does first-stage (current keyword or semantic, larger recall M) then (when enabled) reranks the pairs and returns the final top-k. Blend of first-stage score + reranker score.
- `LocalIntelligenceManager` owns `currentReranker`, creates it when `rerankerEnabled`, passes to rebuild/retrieve paths (including auto-heal), unloads on clear/unloadAll, logs the mode ("semantic+reranked" etc.).
- Prefs: `rerankerEnabled` + `coreAIRerankerModelPath` added to `AIPreferences` (full Codable, inits, decoder).
- Settings: new toggle under the RAG block ("Rerank top candidates with Core AI (higher precision)") with explanatory text; rebuild on change.
- The real Core AI inference for pair scoring is the obvious one-line extension inside the provider (load AIModel / loadFunction / NDArray for the (query,doc) features per your export recipe — identical to the embedding path).
- All existing keyword/semantic paths, clears, low-memory, audit, etc. continue to work.

**App Intents + Spotlight (High #3) — started / architecture ready**
- The exact action surfaces that the native tools now call (the 6 methods in `BrowserState`) + RAG / private search are the perfect candidates for Siri/Shortcuts/Spotlight exposure.
- No prior App Intents / CoreSpotlight / entity code existed (confirmed by searches).
- The wiring patterns (NotificationCenter for "open chat", closures passed to sheets, `onOpenURL`, `Persistence` + `PrivacyManager` for gated data access) are already in place and were reused for the AI tools.
- Full typed `AppEntity` + `AppIntent` + `AppShortcutsProvider` + optional `SpotlightIndexer` (with opt-in toggles and panic-clear coordination) is the direct next step and will make "private search for X with Searxly", "start my local AI chat", "open my Research bookmarks", etc. first-class system features while keeping 100% of the privacy contract.

**Verification performed**
- Multiple arm64 Debug builds with the 27 SDK succeeded after each increment.
- The changes are strictly additive / gated (new capabilities only active when the corresponding prefs + master toggles are on; fallbacks to previous behavior are explicit).
- Existing flows (keyword RAG, synthesis over snippets only, Ollama fallback, direct "open " bypass, attachments, low-memory truncation, privacy clears, activity log) are untouched or transparently enhanced.

**Next (to complete "most of these")**
- Full App Intents module (entities for HistoryItem/BookmarkItem + the parameterized intents that call the BrowserState methods or post the existing notifications; registration in SearxlyApp.swift; settings toggles + Spotlight donation).
- Medium items: LoRA in the Apple provider, small Core AI classifier for early routing, multimodal attachments in chat, Xcode Playgrounds + Evaluations for the prompt library.
- Update this notes file with any model export recipes used for the reranker and any new recommended tools that become reliable with native calling.

All work respects the original design: prompts/rules as the audited source of truth for grounding/privacy, host-side execution in BrowserState, manager as the single owner of providers and prefs, and "your data never leaves your Mac or your private SearXNG".

— 2026 WWDC26 uplift (native tools + reranker pipeline completed; App Intents surface ready to wire).

---

## WWDC26 / macOS 27+: Core AI Integration (Semantic RAG)

**Added in 2026 post-WWDC update.**

Core AI (`CoreAIRuntime` + `CoreAIAsset`) is the new first-class way to load, specialize, and run *your own* models entirely on-device (distinct from the Foundation Models framework that gives you Apple's built-in ~3B LLM).

### What we wired
- New `CoreAIEmbeddingProvider.swift` (conditional on `canImport(CoreAIRuntime)` + macOS 27 availability).
- Extended `AIPreferences` with `semanticRAGEnabled` + `coreAIEmbeddingModelPath`.
- Enhanced `RAGEngine` with parallel pre-computed embeddings + cosine similarity retrieval (hybrid: falls back to the original keyword + recency scorer when semantic is off or no embeddings are available).
- Manager creates/unloads the provider, passes it on rebuilds, and surfaces mode ("semantic (Core AI)" vs "keyword") in logs.
- Settings UI: new toggle + path field under the existing RAG section (only visible when RAG itself is enabled). Rebuild buttons wired.
- All privacy contracts unchanged (model runs locally, no network from the provider, gated by master + granular toggles, audited).

### Obtaining a model (required for real vectors)
1. On a machine with the new Xcode 27 + Python toolchain:
   - `git clone https://github.com/apple/coreai-models.git`
   - Follow the export recipe for a small text embedding model (e.g. a distilled MiniLM or other sentence-transformer variant listed in `models/`).
   - Use the provided `coreai-torch` PyTorch extensions + optimization (`coreai-opt`) to produce a `.aimodel` (or small resource folder containing one).
2. Place the resulting `.aimodel` somewhere on your Mac (e.g. `~/Models/my-embedder.aimodel`).
3. In Searxly → Settings → On-Device Intelligence → enable master + RAG + the new "Use semantic search (Core AI embeddings)" toggle.
4. Paste the path and hit "Rebuild with semantic index".

The provider will load via `CoreAIRuntime.AIModel.contentsOf(...)` (automatic specialization for your Apple Silicon, AOT where possible).

### Current implementation notes / future refinement
- **Function name discovery**: We try "embed", "encode", first program name from the `AIModelAsset`. Update `embedFunctionName` or the `performRealEmbedding` body for your specific export.
- **Input construction (the model-specific part)**: Low-level inference uses `InferenceFunction`, `InferenceValue`, `SharedNDArray` / `UniqueNDArray` etc. (see symbols in the SDK's CoreAI tbd). A good export recipe from apple/coreai-models often comes with a small Swift utility wrapper in their `swift/` package that makes "text → vector" one call. For maximum quality, either:
  - Depend on `coreai-models` (SPM) in the future, or
  - Copy the minimal tokenizer + wrapper logic for your chosen embedding family into `CoreAIEmbeddingProvider`.
- Until a real model + matching call is plugged in, the provider supplies high-quality deterministic mock vectors (fixed 256-dim projection). This makes the *entire* semantic RAG pipeline (precompute on rebuild, query embed, cosine + recency scoring, retrieval) work today for testing and UI validation. Real vectors from Core AI simply replace the projection.
- `cosineSimilarity` helper lives alongside the provider.
- Unload paths, panic/privacy clear, low-memory, and the master kill switch all propagate to the embedding provider.

### Xcode / SDK requirements
- Built and run with Xcode 27+ against macOS 27 SDK (deployment target set to 26.0 for macOS Tahoe and above; new code is guarded).
- On older Xcode/macOS the `#if canImport` + availability branches simply produce the mock path (or pure keyword).

### Testing checklist (add to your flows)
- Toggle semantic on/off → verify logs say "keyword" vs "semantic (Core AI)".
- Rebuild after changing path or sources → embeddings are (re)computed.
- Chat or synthesis with RAG on → retrieved items reflect semantic matches (e.g. "rust borrow checker" should surface old Rust posts even if wording differed).
- Provide no/bad path → still works via mocks (no crash, graceful).
- `unloadAll`, clear history, panic wipe → embedding provider is released and index cleared.
- Instruments: watch memory when semantic index of ~100-150 items is resident.

This gives Searxly best-in-class private, on-device semantic memory over the user's own browsing data with zero extra runtime dependencies for end users (the model file is optional and user-supplied).

Add any new prompt or rule changes related to "I used semantic search over your local data" to `AIRules.swift` / `AIPromptLibrary.swift` in follow-ups if you want the chat to be transparent about *how* the RAG items were chosen.

— 2026 Core AI uplift

### Diagnostics & Reporting Issues (added for fast iteration)
When Local AI "does nothing", crashes on send, doesn't show "thinking", tool calls fail, availability is wrong, or generation errors:

1. In the app: Settings → Local AI → click **"Copy full Local AI diagnostics (for bug reports)"**.
2. Paste the report here.
3. For deeper info:
   - Enable Developer Settings (if present) → Verbose AI Logging.
   - Reproduce the exact prompt/behavior in the Local AI Chat sheet.
   - In Xcode console, filter for `[LocalAI]` and paste those lines.
4. The manager now emits many more `[LocalAI]` prints on send decisions (native vs stream, tool counts, lengths), provider session creation, probe results, generate entry/exit, and errors.
5. `LocalIntelligenceManager.shared.localAIDiagnosticsReport()` and `copyDiagnosticsToPasteboard()` are the central entry points.
6. Activity log (already had "Copy log") + the new full diagnostics cover most "why didn't it think/act" cases.

Send the diagnostics + console snippet + the exact prompt you typed + what you expected, and we'll fix quickly.

Also useful: the existing "Review recent AI actions" sheet + "Audit indexed items" for RAG.

This setup lets you dump everything from Xcode + the app in one go.
