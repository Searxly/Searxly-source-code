//
//  TabNavigationHistory.swift
//  Searxly
//
//  Per-tab back/forward stack for native SERP states alongside WKWebView page history.
//

import Foundation

enum TabBrowseDestination {
    case home
    case search(SearchSnapshot)
    case web(url: String, title: String)
}

struct SearchSnapshot {
    var searchText: String
    var searchResults: [SearXNGResult]
    var lastSearchQuery: String
    var lastEffectiveSearchQuery: String
    var currentSearchCategory: String?
    var searchErrorMessage: String?
    var lastSearchInstanceURL: String?
    var searchPageNo: Int
    var canLoadMoreResults: Bool
    var knowledgePanelState: KnowledgePanelDisplayState
}

final class TabNavigationHistory {
    private var backStack: [TabBrowseDestination] = []
    private var forwardStack: [TabBrowseDestination] = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func pushBack(_ entry: TabBrowseDestination) {
        backStack.append(entry)
        forwardStack.removeAll()
    }

    /// Records the current page on the back stack without discarding forward entries.
    func appendBack(_ entry: TabBrowseDestination) {
        backStack.append(entry)
    }

    func popBack() -> TabBrowseDestination? {
        backStack.popLast()
    }

    func pushForward(_ entry: TabBrowseDestination) {
        forwardStack.append(entry)
    }

    func popForward() -> TabBrowseDestination? {
        forwardStack.popLast()
    }

    func clear() {
        backStack.removeAll()
        forwardStack.removeAll()
    }
}