//
//  BrowserState+SiteNavigation.swift
//  Searxly
//
//  Tab/site actions: open URLs in tabs, bookmark, agentic openWebsite resolution.
//  Extracted from SearchCoordinator.swift.
//

import Foundation
import SwiftUI
import WebKit

extension BrowserState {

    // MARK: - Tab actions

    /// Opens the given URL strings each in their own new browser tab (caps at 6).
    func openResultsInTabs(urls: [String]) {
        var opened = 0
        var lastOpened: BrowserTab?
        for raw in urls {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let withScheme = t.contains("://") ? t : "https://" + t
            guard let url = URL(string: withScheme) else { continue }
            if opened >= 6 { break }
            let tab = BrowserTab(initialURL: url)
            tabs.append(tab)
            lastOpened = tab
            opened += 1
        }
        if let last = lastOpened {
            selectedTabID = last.id
            showingWebContent = true
        }
    }

    /// Bookmarks a URL with an optional note. Dedupes by URL. Caps list at 200.
    func bookmarkWithNote(url: String, title: String, note: String?) {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty else { return }
        bookmarks.removeAll { $0.url == cleanURL }

        let baseTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (URL(string: cleanURL)?.host ?? "Untitled")
            : title.trimmingCharacters(in: .whitespacesAndNewlines)

        let displayTitle: String
        if let n = note?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            displayTitle = "\(baseTitle) — \(n)"
        } else {
            displayTitle = baseTitle
        }

        let item = BookmarkItem(url: cleanURL, title: displayTitle, note: note?.trimmingCharacters(in: .whitespacesAndNewlines))
        bookmarks.insert(item, at: 0)
        if bookmarks.count > 200 { bookmarks.removeLast(bookmarks.count - 200) }
        saveAllData()
    }

    /// Creates a new private (ephemeral) tab, sets the search query, and triggers a SearXNG-backed search.
    func createNewPrivateSearchTab(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let tab = BrowserTab(privacyMode: .privateEphemeral, kind: .web)
        tabs.append(tab)
        selectedTabID = tab.id
        showingWebContent = false
        searchText = trimmed
        lastSearchQuery = trimmed

        Task { @MainActor in
            performSearchOrLoadInWebKit()
        }
    }

    // MARK: - Agentic site resolution

    /// Resolves a natural-language site description to a URL and opens it in a new tab.
    /// Uses OfficialEntityDatabase + private SearXNG. Falls back to a private search tab.
    func openWebsite(description: String) {
        let trimmed = cleanOpenDescription(description)
        guard !trimmed.isEmpty else { return }

        if let directURL = smartURL(from: trimmed) {
            openDirectWebsite(directURL, originalDescription: trimmed)
            return
        }

        if let trusted = SiteResolver.trustedURL(for: trimmed) {
            openDirectWebsite(trusted, originalDescription: trimmed)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            let localMgr = LocalSearxngManager.shared
            if localMgr.projectFolderExists {
                let hasLocal = self.searxInstances.contains {
                    $0.url.hasPrefix("http://localhost:8080") || $0.url.hasPrefix("http://127.0.0.1:8080")
                }
                if hasLocal, !(await localMgr.isLocalWebReady()) {
                    await localMgr.ensureReadyAndRunning()
                }
            }

            let searchQuery = SiteResolver.resolutionQuery(for: trimmed)
            var opened = false
            var resolutionPath = "search+scored"

            do {
                let (res, _) = try await SearXNGService.shared.searchWithFallback(
                    query: searchQuery,
                    instances: self.searxInstances,
                    language: Localization.searchLanguageCode
                )

                let filteredForScorer = res.filter { r in
                    let host = (URL(string: r.url)?.host ?? r.url).lowercased()
                    let title = r.title.lowercased()
                    let isNews = host.contains("cnbc") || host.contains("bbc") || host.contains("nytimes") ||
                                 host.contains("reuters") || host.contains("bloomberg") || host.contains("forbes") ||
                                 host.contains("gizmodo") || host.contains("techcrunch") || host.contains("theverge") ||
                                 host.contains("arstechnica") || host.contains("wired") || host.contains("engadget") ||
                                 host.contains("mashable") || host.contains("businessinsider") ||
                                 (title.contains("news") && !title.contains("official"))
                    let isMetaXArticle = (title.contains("rebrand") || title.contains("formerly twitter") ||
                                          title.contains("x is") || title.contains("twitter rebrand")) &&
                                         !title.contains("official") &&
                                         (trimmed.lowercased() == "x" || trimmed.lowercased().contains("x twitter"))
                    return !isNews && !isMetaXArticle
                }

                if let best = SiteResolver.bestSafeCandidate(
                    for: trimmed,
                    from: filteredForScorer.map { (title: $0.title, url: $0.url) }
                ), best.shouldAutoOpen {
                    self.openDirectWebsite(best.url, originalDescription: trimmed)
                    opened = true
                    resolutionPath = "search+high-authority-scored"
                }
            } catch {
                // fall through to fallback
            }

            if !opened {
                self.createNewPrivateSearchTab(query: trimmed)
                resolutionPath = "fallback-search-tab"
            }

            if DeveloperSettings.shared.isEnabled && DeveloperSettings.shared.verboseSearXNGLogging {
                print("[SiteResolver] openWebsite resolutionPath=\(resolutionPath) query=\(searchQuery) trimmed=\(trimmed) opened=\(opened)")
            }
        }
    }

    private func openDirectWebsite(_ url: URL, originalDescription: String) {
        clearNativeSearch()
        let tab = BrowserTab(initialURL: url)
        tabs.append(tab)
        selectedTabID = tab.id
        showingWebContent = true
        searchText = url.absoluteString
        lastSearchQuery = originalDescription
    }

    // MARK: - Helpers

    private func cleanOpenDescription(_ input: String) -> String {
        var desc = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !desc.isEmpty else { return "" }

        let lower = desc.lowercased()
        let prefixesToStrip = [
            "open the ", "open ",
            "go to the ", "go to ",
            "visit the ", "visit ",
            "take me to the ", "take me to ",
            "the "
        ]
        for prefix in prefixesToStrip {
            if lower.hasPrefix(prefix) {
                desc = String(desc.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        let fluffSuffixesAndInfixes = [
            " official website", " official site", " official homepage", " official web site",
            "'s official website", "'s official site", "'s official homepage",
            " website", " site", " homepage", " web page", " page",
            "'s", " elon musk", " musk", " elon"
        ]
        var lower2 = desc.lowercased()
        for term in fluffSuffixesAndInfixes {
            if lower2.hasSuffix(term) {
                desc = String(desc.dropLast(term.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                lower2 = desc.lowercased()
            }
            if let range = desc.range(of: term, options: .caseInsensitive) {
                desc = (desc[..<range.lowerBound] + desc[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                lower2 = desc.lowercased()
            }
        }

        let facilityTerms = [" chip facility", " chip fab", " fab", " supercluster", " super cluster",
                             " cluster", " facility", " project", " gigafactory"]
        for t in facilityTerms {
            if let range = desc.range(of: t, options: .caseInsensitive) {
                desc = (desc[..<range.lowerBound] + desc[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let lowerDesc = desc.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lowerDesc == "x" || lowerDesc == "twitter" ||
           lowerDesc.contains("x twitter") || lowerDesc.contains("x rebrand") ||
           lowerDesc.contains("formerly twitter") || lowerDesc.contains("x (twitter)") ||
           lowerDesc.hasPrefix("x ") || lowerDesc.contains(" x ") {
            desc = "x.com"
        }

        return desc.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
