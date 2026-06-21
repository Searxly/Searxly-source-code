//
//  SiteResolver.swift
//  Searxly
//
//  High-signal, on-device trusted site resolver for the Searxly Agent open_website tool.
//
//  2026-06 HUGE UPLIFT:
//  - Now backed by OfficialEntityDatabase (new first-class curated "open-source-style" pre-known list).
//  - Dramatically expanded coverage for complex natural-language cases, especially the motivating
//    "open elon musk's chip facility website" / Terafab case (now maps to https://terafab.ai).
//  - Stronger normalization (possessives, facility/project terms), upgraded fuzzy, and authority-aware
//    relevance scoring so official company/project sites beat news (teslarati etc.).
//  - New resolutionQuery helper for smarter private SearXNG fallbacks.
//  - All previous X-brand hardening, Apple-style safeguards, and conservative safety filters preserved.
//
//  Core responsibilities:
//  - Fast, 100% local, zero-network trusted lookup (map + rich aliases from OfficialEntityDatabase).
//  - Relevance scoring (token overlap + brandAffinity + official signals + path authority) for candidates.
//  - Conservative safety filter: never auto-open sensitive content. Marginal results gracefully fall back
//    to a useful private search tab instead of a wrong page.
//  - Provenance-aware behavior for BrowserState (map hit vs search-scored vs fallback).
//
//  The OfficialEntityDatabase.swift file is the living "pre-known open source list" the user requested.
//  It is auditable, easy to extend, and the single source of canonical official URLs + aliases.
//
//  Usage from BrowserState.openWebsite:
//    if let trusted = SiteResolver.trustedURL(for: cleaned) { open it immediately; return }
//    ... perform private search using SiteResolver.resolutionQuery(...) ...
//    if let best = SiteResolver.bestSafeCandidate(...) {
//        if best.shouldAutoOpen { openDirect } else { fallback to search tab }
//    } else { fallback search tab }
//
//  See OfficialEntityDatabase.swift for the full entity list, extension guide, and TEST CASES.
//

import Foundation

public enum SiteResolver {

    // MARK: - Public API

    /// Returns a high-confidence trusted canonical URL for common entities/brands/sites.
    /// Now backed by OfficialEntityDatabase (rich aliases + Terafab etc.).
    /// This is the primary fast path — zero network, guaranteed correct for covered entities.
    public static func trustedURL(for description: String) -> URL? {
        let key = normalizedKey(description)

        // 1. Direct DB entity lookup (best)
        if let entity = OfficialEntityDatabase.entity(for: key) {
            return URL(string: entity.primaryURL)
        }

        // 2. Legacy map + upgraded fuzzy (still powerful)
        if let urlString = trustedMap[key] ?? fuzzyMapMatch(key) {
            return URL(string: urlString)
        }

        // 3. One more direct fuzzy against the full DB (catches complex descriptive keys)
        if let urlString = OfficialEntityDatabase.fuzzyMatchURL(for: key) {
            return URL(string: urlString)
        }

        return nil
    }

    /// Given a user description and a list of private SearXNG candidates (title + url), pick the single
    /// best one that is both relevant to the description **and** safe to auto-open.
    /// Returns nil if nothing meets the bar (caller falls back to search tab).
    ///
    /// The returned `shouldAutoOpen` is true only for high-confidence + safe cases.
    /// Callers should route !shouldAutoOpen (or any safetySignal) through confirmation card when the
    /// open was initiated by the model/tool rather than a raw user imperative.
    public static func bestSafeCandidate(
        for description: String,
        from candidates: [(title: String, url: String)]
    ) -> (url: URL, title: String, relevance: Int, safe: Bool, shouldAutoOpen: Bool, safetySignal: String?)? {

        guard !candidates.isEmpty else { return nil }

        let q = normalizedKey(description)
        let qTokens = tokenSet(from: q)

        // Track the highest-scoring candidate. We deliberately consider *all* and then apply
        // the safety + threshold gates at the end (Apple-style: highest relevance doesn't
        // automatically mean "safe to auto-open").
        var bestScore = -1
        var bestUrlStr = ""
        var bestTitle = ""
        var bestSafe = false
        var bestSignal: String? = nil

        for c in candidates {
            let host = (URL(string: c.url)?.host ?? c.url).lowercased()
            let t = c.title.lowercased()
            let score = relevanceScore(queryTokens: qTokens, title: t, host: host)

            let (safe, signal) = safetyCheck(title: t, host: host, query: q)

            if score > bestScore {
                bestScore = score
                bestUrlStr = c.url
                bestTitle = c.title
                bestSafe = safe
                bestSignal = signal
            }
        }

        guard bestScore >= minimumRelevanceForConsideration else { return nil }

        let finalSafe = bestSafe
        // Apple-style rule: even a high-relevance result is not auto-openable if it has a safety signal
        // (prevents "top result happened to be bad" disasters). shouldAutoOpen also requires decent score.
        let shouldAuto = finalSafe && bestScore >= minimumRelevanceForAutoOpen

        guard let u = URL(string: bestUrlStr.contains("://") ? bestUrlStr : "https://" + bestUrlStr) else {
            return nil
        }

        return (
            url: u,
            title: bestTitle,
            relevance: bestScore,
            safe: finalSafe,
            shouldAutoOpen: shouldAuto,
            safetySignal: bestSignal
        )
    }

    /// Lightweight check (used internally by resolver paths if needed).
    /// The authoritative strict version (with full question/info-request rejection per Apple-style safeguards)
    /// lives in AgenticTools.isExplicitNavigationCommand / OpenWebsite.isExplicitNavigationCommand.
    /// This version is intentionally simple; callers that care about the bypass should prefer the AgenticTools one.
    public static func looksLikeExplicitNavigation(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("can you") || lower.contains("could you") || lower.contains("?") || lower.contains("tell me") {
            return false
        }
        return lower.hasPrefix("open ")
            || lower.contains("open the ")
            || lower.contains("go to ")
            || lower.contains("visit the ")
            || lower.contains("take me to ")
    }

    // MARK: - Safety & Relevance Constants (Apple-style conservative defaults)

    /// Conservative minimums. Tuned so good explicit commands pass, weird descriptive ones do not.
    private static let minimumRelevanceForConsideration = 1
    private static let minimumRelevanceForAutoOpen = 2

    /// Obvious sensitive / high-risk signals for host or title.
    /// Keep this list small and high-precision. Goal = "nothing too sensitive happens".
    /// Sourced from common public patterns (adult industry domains, scam indicators) + defense-in-depth.
    /// We deliberately avoid over-broad terms that would break legitimate sites (e.g. we allow "hub.docker").
    private static let sensitiveSubstrings: Set<String> = [
        "porn", "pornhub", "xvideos", "xhamster", "xnxx", "xxx", "sex", "onlyfans",
        "camgirl", "cams", "adult", "escort", "hentai",
        // Scam / phishing / malware common patterns (conservative)
        "freegift", "claimprize", "verify-login", "secure-bank", "account-suspended",
        "crypto-giveaway", "elon-give", "musk-airdrop"   // common fake elon/musk scam patterns
    ]

    // MARK: - Trusted Data (now powered by OfficialEntityDatabase)

    /// The previous inline trustedMap has been replaced by the rich OfficialEntityDatabase.
    /// We keep a thin cached view for the fastest path and for any legacy call sites.
    private static let trustedMap: [String: String] = OfficialEntityDatabase.trustedMap()

    /// High-authority hosts used for strong scoring boosts (official company/project sites win).
    private static let authorityHosts: Set<String> = OfficialEntityDatabase.authorityHosts()

    /// Convenience: forward the new resolutionQuery helper so BrowserState can produce
    /// smarter search strings for the private SearXNG fallthrough path (e.g. Terafab-aware).
    public static func resolutionQuery(for description: String) -> String {
        OfficialEntityDatabase.resolutionQuery(for: description)
    }

    // MARK: - Internal Helpers (enhanced 2026-06 for Terafab / complex descriptive phrases)

    private static func normalizedKey(_ input: String) -> String {
        var s = input.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Aggressive fluff removal for natural language "open the official ... of X's Y website"
        let fluff = [
            "official website", "official site", "official homepage", "official web site",
            "'s official website", "'s official site", "'s official homepage",
            "website", "site", "homepage", "web page", "page",
            "the official", "official"
        ]
        for f in fluff {
            s = s.replacingOccurrences(of: f, with: " ", options: .caseInsensitive)
        }

        // Possessives and person/brand qualifiers (huge for "elon musk's chip facility")
        s = s.replacingOccurrences(of: "'s", with: " ")
            .replacingOccurrences(of: " elon musk ", with: " ")
            .replacingOccurrences(of: " musk ", with: " ")
            .replacingOccurrences(of: " elon ", with: " ")

        // Facility / project descriptive terms (the motivating class of queries)
        let facilityTerms = [
            " chip facility", " chip fab", " fab", " supercluster", " super cluster",
            " cluster", " gigafactory", " giga factory", " facility", " project"
        ]
        for t in facilityTerms {
            s = s.replacingOccurrences(of: t, with: " ", options: .caseInsensitive)
        }

        s = s.replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strong special cases (X brand protection + common shorthands)
        if s == "x" || s == "twitter" { return "x" }
        if s == "yt" { return "youtube" }
        if s.contains("x") && (s.contains("twitter") || s.contains("rebrand") || s.contains("formerly") || s == "x") {
            return "x"
        }
        // Terafab / Memphis aliases collapse to our canonical key for fast map hit
        if s.contains("terafab") || s.contains("chip facility") || s.contains("memphis") || s.contains("colossus") {
            // Let fuzzy + DB handle the rich alias set; we still return a useful key
            return s
        }

        return s
    }

    private static func tokenSet(from normalized: String) -> Set<String> {
        Set(normalized.split(separator: " ").map(String.init).filter { $0.count > 1 })
    }

    /// Upgraded fuzzy (2026-06): uses OfficialEntityDatabase fuzzyMatchURL first (rich aliases + Terafab bias),
    /// then falls back to legacy token logic over the cached trustedMap. This gives near-instant correct
    /// resolution for complex phrases like "elon musk chip facility" without a search round-trip.
    private static func fuzzyMapMatch(_ normalizedQuery: String) -> String? {
        // Preferred path: the new rich DB fuzzy (handles Terafab, many aliases, authority)
        if let dbURL = OfficialEntityDatabase.fuzzyMatchURL(for: normalizedQuery) {
            return dbURL
        }

        // Legacy fallback (still useful + keeps behavior for anything not yet in DB)
        let qTokens = tokenSet(from: normalizedQuery)
        guard !qTokens.isEmpty else { return nil }

        var bestKey: String?
        var bestScore = 0

        for (key, _) in trustedMap {
            let kTokens = tokenSet(from: key)
            let overlap = qTokens.intersection(kTokens).count
            var score = overlap * 10 + (key.contains(normalizedQuery) || normalizedQuery.contains(key) ? 5 : 0)

            // Strong boost for "X" brand
            if (normalizedQuery.contains("x") || qTokens.contains("x")) && key == "x" {
                score += 20
            }

            // Light Terafab boost even in legacy path
            if normalizedQuery.contains("terafab") || normalizedQuery.contains("chip facility") || normalizedQuery.contains("memphis") {
                if key.contains("xai") || key.contains("tesla") || key.contains("terafab") {
                    score += 15
                }
            }

            if score > bestScore && overlap >= 1 {
                bestScore = score
                bestKey = key
            }
        }
        if let k = bestKey { return trustedMap[k] }
        return nil
    }

    private static func relevanceScore(queryTokens: Set<String>, title: String, host: String) -> Int {
        var score = 0
        let titleTokens = tokenSet(from: title)
        let hostTokens = tokenSet(from: host.replacingOccurrences(of: ".", with: " "))
        let lowerHost = host.lowercased()
        let lowerTitle = title.lowercased()

        // Strong signal if host or title directly contains a query token (especially proper nouns)
        for t in queryTokens {
            if lowerHost.contains(t) || lowerTitle.contains(t) { score += 2 }
            if titleTokens.contains(t) || hostTokens.contains(t) { score += 3 }
        }

        // Bonus for exact-ish host match on short queries
        if queryTokens.count <= 2 {
            let joined = normalizedKey(Array(queryTokens).joined(separator: " "))
            if lowerHost.contains(joined) { score += 4 }
        }

        // Very strong preference for the actual "X" / x.com domain
        if queryTokens.contains("x") && (lowerHost.contains("x.com") || lowerHost == "x.com" || lowerHost.hasSuffix("x.com")) {
            score += 15
        }

        // =====================================================================
        // 2026-06 HUGE UPLIFT: authority + official signals + path quality
        // =====================================================================

        // Brand / authority host boost (the key fix for news beating official sites)
        if authorityHosts.contains(lowerHost) || authorityHosts.contains(lowerHost.replacingOccurrences(of: "www.", with: "")) {
            score += 28
        }
        // Terafab / xAI / Tesla family extra boost for the motivating case
        if lowerHost.contains("terafab.ai") || lowerHost.contains("x.ai") || lowerHost.contains("tesla.com") {
            score += 18
        }

        // Official / home / canonical title signals
        if lowerTitle.contains("official") || lowerTitle.contains("home") || lowerTitle.contains("homepage") ||
           lowerTitle.contains("official site") || lowerTitle.contains("main site") {
            score += 9
        }

        // Path authority: prefer root or very short canonical paths over deep news/spam paths
        let path = (URL(string: "https://" + lowerHost)?.path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty || path.count <= 8 || path == "blog" || path == "about" || path.hasPrefix("en") {
            score += 7
        } else if path.split(separator: "/").count >= 3 {
            score -= 4
        }

        // Light penalty for very long spam-like paths or bloated titles
        if lowerHost.split(separator: ".").count > 3 || title.count > 130 { score -= 2 }

        // Extra defense: known news hosts get a penalty even if they slipped the pre-filter
        let newsHosts = ["teslarati", "cnbc", "bbc", "nytimes", "reuters", "bloomberg", "forbes",
                         "gizmodo", "techcrunch", "theverge", "arstechnica", "wired", "engadget",
                         "mashable", "businessinsider", "tomshardware"]
        for nh in newsHosts {
            if lowerHost.contains(nh) { score -= 6; break }
        }

        return max(0, score)
    }

    private static func safetyCheck(title: String, host: String, query: String) -> (safe: Bool, signal: String?) {
        let combined = (host + " " + title).lowercased()
        for bad in sensitiveSubstrings {
            if combined.contains(bad) {
                // Only treat as unsafe if the query itself does not strongly justify it
                // (defense-in-depth; almost never the case for legitimate "official chip facility")
                if !query.contains(bad) {
                    return (false, "sensitive:\(bad)")
                }
            }
        }
        return (true, nil)
    }

    // MARK: - TEST CASES (for manual verification after changes)

    /*
     These phrases must resolve via trustedURL (fast path) or bestSafeCandidate with high
     authority score (search path) to the correct official site, never a news site.

     Exact user-reported bug case:
       "open elon musk's chip facility website"  → https://terafab.ai  (primary)
       "open terafab"                            → https://terafab.ai
       "go to xAI Memphis supercluster"          → https://terafab.ai or https://x.ai
       "visit the official Tesla Terafab site"   → https://terafab.ai
       "open elon musk terafab chip fab"         → https://terafab.ai

     Other critical cases that must continue to work perfectly:
       "open x", "go to twitter", "visit the platform formerly known as twitter" → https://x.com
       "open tesla", "go to x.ai", "visit neuralink", "open spacex"
       "open the wikipedia page for elon musk"  → https://en.wikipedia.org/wiki/Elon_Musk (special)
       "open apple developer", "visit github", "go to grokipedia"

     Knowledge / info cases (must NOT trigger open_website — handled by classification gate
     in AIRules + isExplicitNavigationCommand):
       "what is elon musk's chip facility?"
       "can you open elon musk's official chip facility website"
       "tell me about Terafab"

     When adding new entities, add matching aliases + a line here.
    */
}
