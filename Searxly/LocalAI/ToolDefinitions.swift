//
//  ToolDefinitions.swift
//
//  DEPRECATED / MIGRATED (2026-06 two-work-tool rework).
//
//  The entire agentic tool system was reduced to exactly two work tools:
//    - web_search   (research / knowledge questions → answer stays in the chat)
//    - open_website (explicit navigation only → opens a tab, usually dismisses the chat sheet)
//
//  All definitions, native Tool + Generable wrappers, user-chip execution helpers,
//  confirmation details, and the assembler now live in the per-tool files under:
//
//      LocalAI/AgenticTools/
//        - WebSearchTool.swift
//        - OpenWebsiteTool.swift
//        - AgenticTools.swift   (the makeCurrent factory + shared helpers)
//
//  This file is kept only as a historical marker and for any stray build references.
//  New call sites should use AgenticTools.makeCurrent(...) directly.
//
//  The old 6-tool surface (search_my_history, open_results_in_tabs, bookmark_with_note,
//  new_private_search_tab, plus the Actions/ folder) has been removed.

import Foundation

// The real implementations are in AgenticTools/.
// The types (WebSearchArgs, WebSearchTool, OpenWebsiteTool, etc.) are defined at module scope
// in the files under AgenticTools/ and are directly visible to the rest of the Searxly target.
//
// 2026-06: open_website now has a massive reliability uplift (OfficialEntityDatabase + SiteResolver
// with rich Terafab / facility aliases, authority scoring, etc.). See OfficialEntityDatabase.swift
// and the session plan.md. This shim remains only for historical/compatibility references.

#if canImport(FoundationModels)
import FoundationModels
#endif

// Thin compatibility note (no longer provides the old SearxlyTools.makeCurrent with 6 params).
// The two-tool factory is AgenticTools.makeCurrent(webSearch:openWebsite:logToolUse:).

// If any code still references the old SearxlyTools enum it will fail at compile time
// (intentional — we want to find and update every site during this cleanup).
