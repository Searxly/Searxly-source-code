//
//  AddressSuggestion.swift
//  Searxly
//
//  Lightweight model for mixed (history + bookmarks + static) address bar suggestions.
//  Created as part of the new dedicated Suggestions folder for clean separation.
//  All matching and data stays 100% local.
//

import Foundation

/// What kind of action selecting this row performs.
enum SuggestionAction: Equatable, Hashable {
    case navigateURL
    case searchQuery
}

/// Represents one suggestion shown in the AddressBar dropdown.
/// Supports personal items, popular sites, remote search completions, and direct URL navigation.
struct AddressSuggestion: Identifiable, Equatable, Hashable {
    let id = UUID()
    /// Primary display text (page title, site name, or search phrase).
    let title: String
    /// Secondary line (host, short URL, or "Search" indicator).
    let subtitle: String
    /// If non-nil, selecting should navigate directly to this URL (https:// added if missing).
    /// If nil, the title is treated as a search term.
    let url: String?
    /// True when this came from the user's local browsing history (subject to historyEnabled).
    let isFromHistory: Bool
    /// True when this came from the user's bookmarks.
    let isFromBookmarks: Bool
    /// True when this is a pre-built common / popular entry (never contains user data).
    let isStatic: Bool
    /// True when this search phrase came from remote autocomplete (SearXNG / DuckDuckGo).
    let isRemoteSearch: Bool
    /// True when this came from the user's own past search queries.
    let isFromSearchHistory: Bool

    var action: SuggestionAction { url != nil ? .navigateURL : .searchQuery }

    // Convenience for display / matching source.
    var isPersonal: Bool { isFromHistory || isFromBookmarks || isFromSearchHistory }
    var showsFavicon: Bool { action == .navigateURL && url != nil }

    // For deduping (prefer personal over static when same host).
    var dedupKey: String {
        if let u = url, let host = URL(string: u)?.host?.lowercased() {
            return host
        }
        return title.lowercased()
    }

    // MARK: - Initializers for different sources

    /// From history item.
    /// Defensive: if the persisted title looks crossed (a well-known brand name attached to a completely
    /// different host, e.g. "Speedtest" title for an x.com URL), fall back to the host so the
    /// suggestion row is truthful. Matching is now brand-specific so that a host like "x.com" does not
    /// "protect" a title that claims "Speedtest".
    static func fromHistory(_ item: HistoryItem) -> AddressSuggestion {
        let derivedHost = URL(string: item.url)?.host?.replacingOccurrences(of: "www.", with: "") ?? item.url
        var displayTitle = item.title.isEmpty ? derivedHost : item.title

        if shouldOverrideTitleForMismatchedBrand(title: displayTitle, host: derivedHost) {
            displayTitle = derivedHost
        }

        return AddressSuggestion(
            title: displayTitle,
            subtitle: derivedHost,
            url: item.url,
            isFromHistory: true,
            isFromBookmarks: false,
            isStatic: false,
            isRemoteSearch: false,
            isFromSearchHistory: false
        )
    }

    /// From bookmark item.
    /// Light defensive guard (bookmarks are explicit saves, but still protect against obviously crossed data).
    /// Bookmarks can surface via title contains (even without host match), so this override is important
    /// to avoid showing "Speedtest" for a bookmark whose URL host is x.com when the user types "test".
    static func fromBookmark(_ item: BookmarkItem) -> AddressSuggestion {
        let derivedHost = URL(string: item.url)?.host?.replacingOccurrences(of: "www.", with: "") ?? item.url
        var displayTitle = item.title.isEmpty ? derivedHost : item.title

        if shouldOverrideTitleForMismatchedBrand(title: displayTitle, host: derivedHost) {
            displayTitle = derivedHost
        }

        return AddressSuggestion(
            title: displayTitle,
            subtitle: derivedHost,
            url: item.url,
            isFromHistory: false,
            isFromBookmarks: true,
            isStatic: false,
            isRemoteSearch: false,
            isFromSearchHistory: false
        )
    }

    /// Returns true if the title appears to claim a famous brand (e.g. contains "speedtest")
    /// but the host does not look like it belongs to that brand.
    /// This prevents crossed suggestions like "Speedtest" (title) + "x.com" (domain) from appearing
    /// when the user types short queries like "test" that match the stored (wrong) title.
    private static func shouldOverrideTitleForMismatchedBrand(title: String, host: String) -> Bool {
        let t = title.lowercased()
        let h = host.lowercased()

        // brand token that might appear in a title -> host substrings that legitimately belong to it
        let checks: [(brand: String, hostTokens: [String])] = [
            ("speedtest", ["speedtest", "ookla"]),
            ("speed test", ["speedtest", "ookla"]),
            ("youtube", ["youtube", "youtu.be"]),
            ("github", ["github"]),
            ("google", ["google"]),
            ("gmail", ["gmail", "google"]),
            ("twitter", ["twitter", "x.com"]),
            ("x.com", ["x.com", "twitter"]),
            ("x / twitter", ["x.com", "twitter"]),
            ("netflix", ["netflix"]),
            ("reddit", ["reddit"]),
            ("amazon", ["amazon"]),
            ("apple", ["apple"]),
            ("spotify", ["spotify"]),
            ("steam", ["steam", "steampowered"]),
            ("discord", ["discord"]),
            ("twitch", ["twitch"]),
        ]

        for (brand, tokens) in checks {
            if t.contains(brand) {
                let hostCompatibleWithThisBrand = tokens.contains { token in
                    h.contains(token)
                }
                if !hostCompatibleWithThisBrand {
                    return true // title claims this brand, but host doesn't match → override
                }
            }
        }
        return false
    }

    /// From curated static popular entry (title + optional URL or search term).
    static func fromStatic(title: String, url: String?, subtitle: String? = nil) -> AddressSuggestion {
        let sub = subtitle ?? (url.flatMap { URL(string: $0)?.host } ?? "Common site")
        return AddressSuggestion(
            title: title,
            subtitle: sub,
            url: url,
            isFromHistory: false,
            isFromBookmarks: false,
            isStatic: true,
            isRemoteSearch: false,
            isFromSearchHistory: false
        )
    }

    /// Direct navigation to the typed URL (e.g. "Go to github.com/foo").
    static func fromURLNavigation(_ rawInput: String) -> AddressSuggestion {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        let host = URL(string: withScheme)?.host?.replacingOccurrences(of: "www.", with: "") ?? trimmed
        return AddressSuggestion(
            title: trimmed,
            subtitle: host,
            url: withScheme,
            isFromHistory: false,
            isFromBookmarks: false,
            isStatic: false,
            isRemoteSearch: false,
            isFromSearchHistory: false
        )
    }

    /// Search the exact phrase the user typed (Safari-style top row).
    static func fromTypedSearch(_ query: String) -> AddressSuggestion {
        AddressSuggestion(
            title: query,
            subtitle: "Search",
            url: nil,
            isFromHistory: false,
            isFromBookmarks: false,
            isStatic: false,
            isRemoteSearch: false,
            isFromSearchHistory: false
        )
    }

    /// Remote autocomplete search phrase (SearXNG / DuckDuckGo).
    static func fromRemoteSearch(_ query: String) -> AddressSuggestion {
        AddressSuggestion(
            title: query,
            subtitle: "Search suggestion",
            url: nil,
            isFromHistory: false,
            isFromBookmarks: false,
            isStatic: false,
            isRemoteSearch: true,
            isFromSearchHistory: false
        )
    }

    /// A search query the user typed in the past, re-surfaced as a suggestion.
    static func fromSearchHistory(_ query: String) -> AddressSuggestion {
        AddressSuggestion(
            title: query,
            subtitle: "Recent search",
            url: nil,
            isFromHistory: false,
            isFromBookmarks: false,
            isStatic: false,
            isRemoteSearch: false,
            isFromSearchHistory: true
        )
    }
}
