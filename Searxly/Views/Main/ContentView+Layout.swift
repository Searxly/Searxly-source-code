//
//  ContentView+Layout.swift
//  Searxly
//
//  Sidebar layout and address-bar suggestions overlay for ContentView.
//

import SwiftUI
import AppKit
import WebKit

extension ContentView {
    // MARK: - Slim header suggestions

    var slimSuggestionsVisible: Bool {
        !isPureHomeState
            && isAddressBarFocused
            && browserState.shouldShowSuggestionsPanel
            && slimAddressBarFrame.width > 0
            && slimAddressBarFrame.height > 0
    }

    @ViewBuilder
    var slimHeaderSuggestionsOverlay: some View {
        if slimSuggestionsVisible {
            AddressBarSuggestionsView(
                suggestions: browserState.suggestions,
                selectedIndex: browserState.suggestionsSelectedIndex,
                isLoading: browserState.suggestionsIsLoading,
                glassEnabled: glassEnabled,
                toolbarMaterial: toolbarMaterial,
                barCornerRadius: 11,
                maxWidth: slimAddressBarFrame.width,
                onSelect: { suggestion in
                    browserState.selectSuggestion(suggestion)
                },
                onDismiss: {
                    browserState.dismissSuggestionsPanel()
                }
            )
            .frame(width: slimAddressBarFrame.width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .offset(
                x: slimAddressBarFrame.minX,
                y: slimAddressBarFrame.maxY + 6
            )
            .zIndex(500)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.easeOut(duration: 0.14), value: slimSuggestionsVisible)
        }
    }

    // MARK: - Layout

    /// Left sidebar (Arc-style) layout is the ONLY supported layout.
    /// Now reads most state from BrowserState (refactor). Still owns the reduce glass @AppStorage
    /// and FocusState for the address bar (view concerns).
    ///
    /// Sidebar is toggled between narrow rail and expanded list via the chevron buttons only.
    /// Free drag-to-resize has been removed (it was causing persistent lag, glitches, and bad sizes).
    /// Width is always one of the two canonical values from BrowserState (rail or defaultExpanded).
    ///
    /// - For !isPureHomeState (search results or open webpage) we render a single slim header row that places
    ///   a compact AddressBar to the *left* of the RightToolbarControls button cluster. This removes the
    ///   previous separate AddressBar strip, giving the web content / search results list (the focus area)
    ///   significantly more vertical space.
    /// - Pure home keeps its hero centered AddressBar (inside mainContentArea) + the right controls row.
    var sidebarLayout: some View {
        HStack(spacing: 0) {
            // Sidebar width is driven purely by the toggle (chevron). No more free drag/resizer.
            // We use the canonical rail vs expanded widths from BrowserState for consistent, glitch-free behavior.
            SidebarTabList(
                tabs: $browserState.tabs,
                selectedTabID: $browserState.selectedTabID,
                glassEnabled: glassEnabled,
                toolbarMaterial: toolbarMaterial,
                sidebarWidth: browserState.sidebarWidth,
                isCollapsed: browserState.isSidebarCollapsed,
                toggleCollapse: {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                        browserState.toggleSidebarCollapse()
                    }
                },
                newTabAction: newTab,
                newPrivateTabAction: newPrivateTab,
                closeTabAction: closeTab,
                closeAllTabsAction: closeAllTabs,
                moveTab: moveTab,
                pinTabAction: { tab in
                    tab.isPinned.toggle()
                    guard let idx = browserState.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
                    let removed = browserState.tabs.remove(at: idx)
                    // Always insert at the boundary between pinned and regular tabs.
                    // Pinned: moves to end of pinned group. Unpinned: moves to start of regular group.
                    let insertAt = browserState.tabs.filter { $0.isPinned }.count
                    browserState.tabs.insert(removed, at: insertAt)
                },
                duplicateTabAction: { tab in browserState.duplicateTab(tab) },
                muteTabAction: { tab in
                    tab.isMuted.toggle()
                    tab.applyMute()
                    guard let idx = browserState.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
                    let t = browserState.tabs.remove(at: idx)
                    browserState.tabs.insert(t, at: idx)
                },
                forgetDomainAction: forgetDomainInSidebar,
                reopenClosedTabAction: browserState.recentlyClosedSnapshots.isEmpty ? nil : { browserState.reopenLastClosedTab() },
                hasClosedTabs: !browserState.recentlyClosedSnapshots.isEmpty,
                showingSettings: $browserState.showingSettings,
                showingWallet: $browserState.showingWallet,
                showingBookmarks: $browserState.showingBookmarks,
                showingFullHistory: $browserState.showingFullHistory,
                showingDownloads: $browserState.showingDownloads
            )
            .frame(width: browserState.sidebarWidth)

            VStack(spacing: 0) {
                // Right column content (slim header on results/web + main content, or home hero content).
                // The ZStack is used to hoist suggestions above the web content / results without
                // affecting their layout (the inner VStack keeps its normal size).
                ZStack(alignment: .topLeading) {
                    if isPureHomeState {
                        HomeAmbientBackground(
                            glassEnabled: glassEnabled,
                            homeStarsEnabled: homeStarsEnabled
                        )
                    }

                    Color.clear
                        .onChange(of: isAddressBarFocused) {
                            updateSuggestionsFromFocus()
                        }
                    VStack(spacing: 0) {
                        BrowserHeaderView(
                            isPureHomeState: isPureHomeState,
                            glassEnabled: glassEnabled,
                            toolbarMaterial: toolbarMaterial,
                            searchText: $browserState.searchText,
                            isAddressBarFocused: $isAddressBarFocused,
                            showingWebContent: browserState.showingWebContent,
                            browserState: browserState,
                            onSubmit: { submitFromAddressBar() },
                            activeWebView: browserState.activeWebView,
                            canGoBack: browserState.canGoBack,
                            canGoForward: browserState.canGoForward,
                            bookmarks: $browserState.bookmarks,
                            webPageTitle: $browserState.webPageTitle,
                            showingBookmarks: $browserState.showingBookmarks,
                            showingFullHistory: $browserState.showingFullHistory,
                            showingDownloads: $browserState.showingDownloads,
                            showingKeyboardShortcuts: $browserState.showingKeyboardShortcuts,
                            onToggleReaderMode: { browserState.toggleReaderModeAction() },
                            onShowFind: { browserState.showFindInPage() },
                            onOpenLocalAIChat: { browserState.openLocalAIChat() },
                            onBookmarkCurrentPage: { browserState.bookmarkCurrentPage() },
                            onGoBack: { browserState.goBack() },
                            onGoForward: { browserState.goForward() },
                            currentWebDomain: browserState.currentWebDomain,
                            hasPasswordFieldOnPage: browserState.currentPageHasPasswordField,
                            isLikelySignupForm: browserState.currentPageIsLikelyPasswordCreation,
                            onGeneratePasswordForPage: passwordVault.suggestPasswordsEnabled ? {
                                browserState.generateAndFillPasswordOnCurrentPage()
                            } : nil,
                            onSaveLoginFromPage: passwordVault.offerToSaveEnabled ? {
                                presentSaveLoginSheet()
                            } : nil,
                            onFillLogin: passwordVault.autofillEnabled ? { domain, username, password in
                                browserState.fillCurrentPageWithLogin(username: username, password: password)
                                if let entry = passwordVault.entries(forDomain: domain).first(where: { $0.username == username }) {
                                    passwordVault.markEntryUsed(id: entry.id)
                                }
                            } : nil
                        )

                        mainContentArea
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .simultaneousGesture(
                                TapGesture()
                                    .onEnded {
                                        // Dismiss open suggestions (including while loading).
                                        if browserState.shouldShowSuggestionsPanel {
                                            dismissSuggestionsAndBlur()
                                            return
                                        }
                                        // On results/web, tap the content area to leave the slim header bar.
                                        // Skip on pure home — that gesture steals focus from the hero search bar.
                                        if isAddressBarFocused && !isPureHomeState {
                                            dismissSuggestionsAndBlur()
                                        }
                                    }
                            )
                    }

                    slimHeaderSuggestionsOverlay
                }
                .coordinateSpace(name: "mainColumn")
                .onPreferenceChange(AddressBarFramePreferenceKey.self) { frame in
                    slimAddressBarFrame = frame
                }
                    .sheet(item: $browserState.selectedImageForPreview) { result in
                        // Uses the new modular MediaPreviewSheet (Views/SearchResults/) from the 2026 SERP redesign.
                        // Supports both images and videos with correct proxy for high-quality previews.
                        MediaPreviewSheet(
                            result: result,
                            isVideo: browserState.currentSearchCategory == "videos",
                            onOpenPage: {
                                if let url = URL(string: result.url) { loadInWebView(url) }
                                browserState.selectedImageForPreview = nil
                            },
                            proxyBaseURL: browserState.lastSearchInstanceURL ?? browserState.searxInstances.first?.url
                        )
                    }
                    // Focus transfer: when we leave pure home (hero bar) because the user submitted a search,
                    // the hero AddressBar is removed from the tree and the slim header bar appears in its place.
                    // Re-assert focus on the (now visible) slim bar after a tiny delay so the user can
                    // immediately type a refinement or new query without having to click or press ⌘L again.
                    .onChange(of: isPureHomeState) { wasPure, isPure in
                        if wasPure && !isPure && isAddressBarFocused {
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(110))
                                isAddressBarFocused = true
                            }
                        }
                    }
            }
            .background {
                if !isPureHomeState {
                    AdaptiveChrome.appCanvas(resolvedColorScheme, glassEnabled: glassEnabled)
                }
            }

            // MARK: - Global browser keyboard shortcuts (Safari-like)
            // These are always available (even when web nav buttons are not visible in the header).
            // We use tiny hidden buttons so the shortcuts are registered without affecting layout.
            Group {
                // Reload (⌘R) — works on web pages or to re-trigger search in some cases
                Button("Reload") {
                    if browserState.showingWebContent {
                        browserState.reload()
                    } else if !browserState.searchResults.isEmpty {
                        // Re-run the last search if on results
                        performSearchOrLoadInWebKit()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)

                // Back / Forward
                Button("Back") { browserState.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)

                Button("Forward") { browserState.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)

                // Focus / select address bar (⌘L) — works in header or home
                Button("Focus Address Bar") {
                    isAddressBarFocused = true
                }
                .keyboardShortcut("l", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)

                // Close current tab (⌘W)
                Button("Close Tab") {
                    browserState.closeCurrentTab()
                }
                .keyboardShortcut("w", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)

                // Find in page (⌘F) — will show the bar when on a web page
                Button("Find in Page") {
                    browserState.showFindInPage()
                }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)

                // Stop loading (⌘.)
                Button("Stop Loading") {
                    if browserState.showingWebContent {
                        browserState.stopLoading()
                    }
                }
                .keyboardShortcut(".", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)

                // Bookmark current page (⌘D) — also available via toolbar when on web
                Button("Bookmark Current Page") {
                    browserState.bookmarkCurrentPage()
                }
                .keyboardShortcut("d", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)

                // New Tab / New Private Tab (global, in addition to sidebar buttons)
                Button("New Tab") { newTab() }
                    .keyboardShortcut("t", modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)

                Button("New Private Tab") { newPrivateTab() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)

                Button("Reopen Closed Tab") { browserState.reopenLastClosedTab() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)

                Button("Mute Tab") {
                    guard let tab = browserState.tabs.first(where: { $0.id == browserState.selectedTabID }) else { return }
                    tab.isMuted.toggle()
                    tab.applyMute()
                    guard let idx = browserState.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
                    let t = browserState.tabs.remove(at: idx)
                    browserState.tabs.insert(t, at: idx)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)

                // ⌘1–9: jump to tab by position
                ForEach(Array(1...9), id: \.self) { i in
                    Button("Tab \(i)") {
                        let index = i - 1
                        guard index < browserState.tabs.count else { return }
                        browserState.selectedTabID = browserState.tabs[index].id
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(i)")), modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
                }

                // ⌃Tab / ⌃⇧Tab: cycle through tabs
                Button("Next Tab") {
                    let ts = browserState.tabs
                    guard !ts.isEmpty else { return }
                    let idx = ts.firstIndex(where: { $0.id == browserState.selectedTabID }) ?? 0
                    browserState.selectedTabID = ts[(idx + 1) % ts.count].id
                }
                .keyboardShortcut(.tab, modifiers: .control)
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)

                Button("Previous Tab") {
                    let ts = browserState.tabs
                    guard !ts.isEmpty else { return }
                    let idx = ts.firstIndex(where: { $0.id == browserState.selectedTabID }) ?? 0
                    browserState.selectedTabID = ts[(idx - 1 + ts.count) % ts.count].id
                }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geo in
                let divider = AdaptiveChrome.divider(resolvedColorScheme)
                let sidebarW = browserState.sidebarWidth
                let headerH = AdaptiveChrome.slimToolbarRowHeight
                let isExpanded = !browserState.isSidebarCollapsed

                if isPureHomeState {
                    Rectangle()
                        .fill(divider)
                        .frame(width: 1, height: geo.size.height)
                        .offset(x: sidebarW - 1)
                } else {
                    Rectangle()
                        .fill(divider)
                        .frame(
                            width: isExpanded ? geo.size.width : geo.size.width - sidebarW,
                            height: 1
                        )
                        .offset(x: isExpanded ? 0 : sidebarW, y: headerH - 1)

                    Rectangle()
                        .fill(divider)
                        .frame(
                            width: 1,
                            height: isExpanded ? max(0, geo.size.height - headerH) : geo.size.height
                        )
                        .offset(x: sidebarW - 1, y: isExpanded ? headerH : 0)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// AddressBar has been extracted to Views/Components/AddressBar.swift (compact/fluid redesign for sidebar search use).

// (SearchResultCard definition removed — now in Components/SearchResultCard.swift after monster refactor.)

#Preview {
    ContentView()
}
