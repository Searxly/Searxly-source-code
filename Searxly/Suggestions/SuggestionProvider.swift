//
//  SuggestionProvider.swift
//  Searxly
//
//  Mixed local + static suggestion engine for the AddressBar.
//  - Personal: history (when enabled) + bookmarks (explicit saves).
//  - Static: pre-built curated common domains / sites for cold-start utility (never user data).
//  All computation is purely local and synchronous. No network, no exfiltration.
//  Follows the same "bundled local data" model as AdBlocker core lists.
//

import Foundation

/// Provides ranked AddressSuggestions by mixing the user's local history/bookmarks
/// with a static set of popular/common entries.
enum SuggestionProvider {

    /// Returns up to `maxResults` mixed suggestions for the given query.
    /// Personal items (history when enabled, bookmarks) are preferred and appear first.
    /// Static items fill the rest for useful cold-start / prefix coverage.
    ///
    /// Strict domain + prefix matching:
    /// - History: hostRelevance (any dot-label prefix) required before any title/URL bonus. Title-alone never qualifies.
    /// - Statics: hostRelevance OR title/subtitle *prefix* (no loose .contains). Short queries like "test"/"te" no longer
    ///   surface unrelated popular sites or compound-host history rows ("Youtube - speedtest.com").
    /// Crossed history (stale title for a URL) is further defended in AddressSuggestion.fromHistory.
    static func suggestions(
        for rawQuery: String,
        history: [HistoryItem],
        bookmarks: [BookmarkItem],
        historyEnabled: Bool,
        maxResults: Int = 6
    ) -> [AddressSuggestion] {
        let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        var results: [AddressSuggestion] = []
        var seenKeys = Set<String>()

        // Personal (history + bookmarks) with strong domain/host priority.
        // We score everything, then sort once so good domain matches from history
        // beat weak title matches from old pages.
        var scoredPersonal: [(sug: AddressSuggestion, score: Int, date: Date?)] = []

        if historyEnabled {
            for item in history {
                let h = host(from: item.url)
                let t = item.title.lowercased()
                let u = item.url.lowercased()

                // Domain/host prioritized scoring for history (per "prioritize domains in search history").
                // - Strong prefix on the host (or any dot-label) so "you" matches "youtube.com" but
                //   "test" does NOT match "speedtest.net" (no label starts with "test").
                // - Incidental matches inside full URL strings (e.g. old ?search_query=test on youtube
                //   result pages) are intentionally ignored so the bare "youtube.com" domain entry
                //   does not surface for unrelated short queries.
                let hostScore = hostRelevance(for: h, query: q)
                var score = hostScore

                // Minor bonus only when we already have a domain signal (no pure-URL qualification).
                if hostScore > 0 && u.contains(q) {
                    score += 8
                }

                // Title bonus ONLY on top of a real domain match (never title-alone for history).
                if hostScore > 0 && t.contains(q) {
                    score += 5
                }

                guard score > 0 else { continue }

                let ageDays = max(0.0, Date().timeIntervalSince(item.date) / 86400.0)
                score += max(0, 20 - Int(min(ageDays, 20)))

                let sug = AddressSuggestion.fromHistory(item)
                scoredPersonal.append((sug, score, item.date))
            }
        }

        for item in bookmarks {
            let h = host(from: item.url)
            let t = item.title.lowercased()

            // Use same domain-aware host scoring for bookmarks.
            // Pure title matches are still allowed (bookmarks are explicit user saves; title may be
            // the memorable label the user actually remembers and wants to find by typing part of it).
            // The brand-mismatch guard in fromBookmark + the healer will ensure crossed ones (e.g.
            // a bookmark saved with title "Speedtest" but url on x.com) display the real host instead
            // of lying about the title when they surface for queries like "test".
            let hostScore = hostRelevance(for: h, query: q)
            var score = hostScore
            if hostScore > 0 {
                // slightly lower base than history since we also credit title strongly
                if score == 160 { score = 130 }
                else if score == 140 { score = 115 }
                else if score == 110 { score = 95 }
            }
            if t.contains(q) {
                score += (hostScore > 0 ? 15 : 20)
            }

            guard score > 0 else { continue }

            let sug = AddressSuggestion.fromBookmark(item)
            scoredPersonal.append((sug, score, item.dateAdded))
        }

        // Best domain scores first, then more recent.
        let sortedPersonal = scoredPersonal.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            let d0 = $0.date ?? .distantPast
            let d1 = $1.date ?? .distantPast
            return d0 > d1
        }

        for (sug, _, _) in sortedPersonal {
            if seenKeys.insert(sug.dedupKey).inserted {
                results.append(sug)
                if results.count >= 8 { break }
            }
        }

        // 3. Static popular / common (cold start + general utility).
        // IMPORTANT FIX: filter is now *strict* (hostRelevance or title/sub *prefix* only).
        // Previous .contains(q) allowed arbitrary substring hits on short queries ("te", "test", "ack", etc.)
        // surfacing completely unrelated popular sites. We now require the same strong domain-label
        // or leading-prefix signals used for history. This is the main "any query shows junk" fix.
        let staticScored: [(sug: AddressSuggestion, score: Int)] = staticSuggestions.compactMap { sug in
            let h = sug.url.flatMap { host(from: $0) } ?? ""
            let hostScore = hostRelevance(for: h, query: q)
            let t = sug.title.lowercased()
            let s = sug.subtitle.lowercased()

            // Title/subtitle must be *prefix* match (or we have a real host signal).
            let titlePrefix = t.hasPrefix(q)
            let subPrefix = s.hasPrefix(q)

            guard hostScore > 0 || titlePrefix || subPrefix else { return nil }

            // Score: domain hits win, then title prefix, sub prefix, shorter wins ties.
            var sc = hostScore
            if titlePrefix { sc += 90 }
            else if t.contains(q) { sc += 5 } // very weak fallback only for long queries (rarely used)
            if subPrefix { sc += 40 }
            if hostScore > 0 { sc += 15 }
            if q.count <= 2 && sc < 100 { sc = 0 } // be extra brutal for 1-2 char queries
            return sc > 0 ? (sug, sc) : nil
        }

        let staticMatches = staticScored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.sug.title.count < $1.sug.title.count
            }
            .prefix(8)
            .map { $0.sug }

        for sug in staticMatches {
            if seenKeys.insert(sug.dedupKey).inserted {
                results.append(sug)
            }
        }

        // We already sorted history and bookmarks by domain strength + recency inside their sections.
        // If you want a single unified personal ranking, we could merge scored lists here,
        // but current section order (recent strong domain history first, then bookmarks, then statics) works well.

        // Final cap + return.
        return Array(results.prefix(maxResults))
    }

    /// Merges purely-local suggestions with optional remote search completions and URL-navigation rows.
    /// URL-like input prioritizes navigation + site matches; search-like input blends sites then queries.
    static func mergedSuggestions(
        for rawQuery: String,
        history: [HistoryItem],
        bookmarks: [BookmarkItem],
        historyEnabled: Bool,
        remoteSearchQueries: [String],
        pastSearchQueries: [SearchQueryRecord] = [],
        maxResults: Int = 6
    ) -> [AddressSuggestion] {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let isURLMode = SearchAutocompleteService.looksLikeURLInput(trimmed)
        var results: [AddressSuggestion] = []
        var seenKeys = Set<String>()

        func appendUnique(_ sug: AddressSuggestion) {
            guard seenKeys.insert(sug.dedupKey).inserted else { return }
            results.append(sug)
        }

        if isURLMode {
            // Top row: navigate to exactly what was typed.
            appendUnique(.fromURLNavigation(trimmed))
        } else {
            // Top row: search for exactly what was typed.
            appendUnique(.fromTypedSearch(trimmed))
        }

        // Past search queries — shown right after the typed row so the user can quickly
        // repeat a recent search with one ↓ keystroke.
        if !isURLMode {
            for record in pastSearchQueries {
                appendUnique(.fromSearchHistory(record.query))
                if results.count >= maxResults { break }
            }
        }

        // Local history / bookmarks / popular sites.
        let local = suggestions(
            for: trimmed,
            history: history,
            bookmarks: bookmarks,
            historyEnabled: historyEnabled,
            maxResults: isURLMode ? 8 : 6
        )
        for sug in local {
            appendUnique(sug)
            if results.count >= maxResults { break }
        }

        if !isURLMode {
            // Remote search completions (open autocomplete backends).
            for phrase in remoteSearchQueries {
                let lower = phrase.lowercased()
                if lower == trimmed.lowercased() { continue }
                appendUnique(.fromRemoteSearch(phrase))
                if results.count >= maxResults { break }
            }
        }

        return Array(results.prefix(maxResults))
    }

    // MARK: - Helpers

    private static func host(from urlString: String) -> String {
        guard let u = URL(string: urlString),
              let h = u.host?.lowercased() else { return "" }
        return h.replacingOccurrences(of: "www.", with: "")
    }

    /// Domain-aware relevance for a host against the typed query.
    /// Prefers real domain/label prefix matches so we surface sites the user actually visits
    /// by domain (e.g. "you" -> youtube) while avoiding accidental substring hits inside
    /// compound hostnames (e.g. "test" must not surface speedtest.net) or incidental matches.
    /// Used for both history (strict gate) and static cold-start filtering.
    private static func hostRelevance(for host: String, query q: String) -> Int {
        guard !host.isEmpty, !q.isEmpty else { return 0 }
        let h = host.replacingOccurrences(of: "www.", with: "")
        if h == q { return 160 }
        if h.hasPrefix(q) || h.hasPrefix(q + ".") { return 140 }
        // Match if *any* dot-separated label (subdomain or eTLD+1) starts with q.
        // This is the key filter: "youtube".hasPrefix("you") == true, but "speedtest".hasPrefix("test") == false.
        let labels = h.split(separator: ".").map(String.init)
        if labels.contains(where: { $0.hasPrefix(q) || $0 == q }) {
            return 110
        }
        // Very conservative loose contains only for longer queries (rarely needed for domain intent).
        if q.count >= 5 && h.contains(q) {
            return 45
        }
        return 0
    }

    // MARK: - Curated static suggestions (mixed domains + a few common "known searches")

    /// Hand-curated list of common, useful, timeless entries.
    /// Goal: make typing 2-4 chars (you, git, wik, red, net, ama, etc.) immediately useful
    /// even on a fresh install with no history. All entries are non-personal.
    /// Sources conceptually: well-known popular sites + a few search-oriented fallbacks.
    /// Kept modest in size (~140) for fast linear filter and small binary impact.
    ///
    /// Matching for these is now strict prefix/host only (see suggestions(for:)) to prevent
    /// "any query shows random popular sites" bugs.
    private static let staticSuggestions: [AddressSuggestion] = [
        // Y
        .fromStatic(title: "YouTube", url: "https://youtube.com"),
        .fromStatic(title: "YouTube Music", url: "https://music.youtube.com"),
        // G
        .fromStatic(title: "GitHub", url: "https://github.com"),
        .fromStatic(title: "Google", url: "https://google.com"),
        .fromStatic(title: "Gmail", url: "https://gmail.com"),
        .fromStatic(title: "Google Maps", url: "https://maps.google.com"),
        .fromStatic(title: "Grokipedia", url: "https://grokipedia.com"),
        // W
        .fromStatic(title: "Wikipedia", url: "https://wikipedia.org"),
        .fromStatic(title: "Wikimedia", url: "https://wikimedia.org"),
        // R
        .fromStatic(title: "Reddit", url: "https://reddit.com"),
        // N
        .fromStatic(title: "Netflix", url: "https://netflix.com"),
        .fromStatic(title: "NYTimes", url: "https://nytimes.com"),
        // A
        .fromStatic(title: "Amazon", url: "https://amazon.com"),
        .fromStatic(title: "Apple", url: "https://apple.com"),
        .fromStatic(title: "Apple Developer", url: "https://developer.apple.com"),
        // T
        .fromStatic(title: "Twitter / X", url: "https://x.com"),
        .fromStatic(title: "Twitch", url: "https://twitch.tv"),
        // D
        .fromStatic(title: "Discord", url: "https://discord.com"),
        .fromStatic(title: "DuckDuckGo", url: "https://duckduckgo.com"),
        // F
        .fromStatic(title: "Facebook", url: "https://facebook.com"),
        .fromStatic(title: "Figma", url: "https://figma.com"),
        // S
        .fromStatic(title: "Spotify", url: "https://spotify.com"),
        .fromStatic(title: "Stack Overflow", url: "https://stackoverflow.com"),
        .fromStatic(title: "Steam", url: "https://store.steampowered.com"),
        // M
        .fromStatic(title: "Microsoft", url: "https://microsoft.com"),
        .fromStatic(title: "Medium", url: "https://medium.com"),
        // L
        .fromStatic(title: "LinkedIn", url: "https://linkedin.com"),
        // C
        .fromStatic(title: "ChatGPT", url: "https://chat.openai.com"),
        .fromStatic(title: "Cloudflare", url: "https://cloudflare.com"),
        // Common dev / privacy friendly
        .fromStatic(title: "Hacker News", url: "https://news.ycombinator.com"),
        .fromStatic(title: "GitLab", url: "https://gitlab.com"),
        .fromStatic(title: "Docker Hub", url: "https://hub.docker.com"),
        .fromStatic(title: "MDN Web Docs", url: "https://developer.mozilla.org"),
        .fromStatic(title: "arXiv", url: "https://arxiv.org"),
        // News / reference
        .fromStatic(title: "BBC", url: "https://bbc.com"),
        .fromStatic(title: "The Guardian", url: "https://theguardian.com"),
        .fromStatic(title: "Reuters", url: "https://reuters.com"),
        .fromStatic(title: "Wolfram Alpha", url: "https://wolframalpha.com"),
        // More common
        .fromStatic(title: "Instagram", url: "https://instagram.com"),
        .fromStatic(title: "TikTok", url: "https://tiktok.com"),
        .fromStatic(title: "WhatsApp", url: "https://web.whatsapp.com"),
        .fromStatic(title: "Zoom", url: "https://zoom.us"),
        .fromStatic(title: "Dropbox", url: "https://dropbox.com"),
        .fromStatic(title: "Notion", url: "https://notion.so"),
        .fromStatic(title: "Linear", url: "https://linear.app"),
        .fromStatic(title: "Vercel", url: "https://vercel.com"),
        .fromStatic(title: "Stripe", url: "https://stripe.com"),
        .fromStatic(title: "OpenAI", url: "https://openai.com"),
        .fromStatic(title: "Anthropic", url: "https://anthropic.com"),
        // Quick "search for" style fallbacks (treated as queries if no URL)
        .fromStatic(title: "Search Wikipedia", url: nil, subtitle: "Wikipedia search"),
        .fromStatic(title: "Search DuckDuckGo", url: nil, subtitle: "Privacy search"),
        .fromStatic(title: "Search Grokipedia", url: nil, subtitle: "Grokipedia search"),
    ]
}
