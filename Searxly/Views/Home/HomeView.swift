//
//  HomeView.swift
//  Searxly
//
//  Premium home / new-tab hero: ambient starfield, logo, glass search bar.
//

import SwiftUI

private struct HomeTaglineBlock: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 5) {
            Text(Localization.string("home_tagline"))
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.secondary.opacity(colorScheme == .dark ? 0.9 : 0.82))
                .tracking(0.35)

            Text(Localization.string("home_subtitle"))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.tertiary.opacity(0.88))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .tracking(0.25)
                .lineSpacing(2)
        }
        .frame(maxWidth: 420)
    }
}

// MARK: - Home

struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let glassEnabled: Bool

    @Binding var searchText: String
    @FocusState.Binding var isAddressBarFocused: Bool

    let searchErrorMessage: String?
    let showInstanceNotDetected: Bool
    let showEnableAIToolsPrompt: Bool
    let localAIChatEnabled: Bool

    @Bindable var browserState: BrowserState

    let onSubmit: () -> Void
    let onOpenSettings: () -> Void
    let onDismissError: () -> Void
    let onEnableAITools: () -> Void
    let onLaterAITools: () -> Void
    let onOpenLocalAIChat: () -> Void

    @State private var heroRevealed = false
    @State private var addressBarHeight: CGFloat = 52

    var body: some View {
        // Ambient background is hoisted in ContentView (behind header + hero) on pure home.
        GeometryReader { proxy in
                let upwardBias = min(72, proxy.size.height * 0.09)

                VStack {
                    Spacer(minLength: 20)
                        .contentShape(Rectangle())
                        .onTapGesture { dismissHomeFocus() }

                    VStack(alignment: .center, spacing: 0) {
                        logoBlock
                            .padding(.bottom, 18)

                        taglineBlock
                            .padding(.bottom, 26)
                            .heroReveal(heroRevealed, reduceMotion: reduceMotion, delay: 0.06)

                        searchCluster
                            .heroReveal(heroRevealed, reduceMotion: reduceMotion, delay: 0.12)
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(y: -upwardBias)
                    .onAppear { revealHero() }

                    Spacer(minLength: 120)
                        .contentShape(Rectangle())
                        .onTapGesture { dismissHomeFocus() }
                }
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dismissHomeFocus() {
        isAddressBarFocused = false
        browserState.dismissSuggestionsPanel()
    }

    private var logoBlock: some View {
        SearxlyLogo(
            glassEnabled: glassEnabled,
            size: 58,
            style: .hero,
            animated: !reduceMotion,
            showShine: glassEnabled && !reduceMotion,
            showTagline: false
        )
        .heroReveal(heroRevealed, reduceMotion: reduceMotion, delay: 0)
    }

    private var taglineBlock: some View {
        HomeTaglineBlock()
    }

    private var searchCluster: some View {
        VStack(alignment: .center, spacing: 14) {
            heroSearchBarCluster
            statusAffordanceRow
        }
        .overlay(alignment: .top) {
            heroFloatingSuggestionsPanel
        }
    }

    /// Stable layout: hero bar only. Suggestions are a separate floating overlay on `searchCluster`.
    private var heroSearchBarCluster: some View {
        AddressBar(
            text: $searchText,
            isFocused: $isAddressBarFocused,
            showingWebContent: false,
            glassEnabled: glassEnabled,
            toolbarMaterial: glassEnabled ? .ultraThinMaterial : .regularMaterial,
            onSubmit: onSubmit,
            isHero: true,
            onSuggestionsArrowDown: {
                if !browserState.suggestions.isEmpty {
                    browserState.suggestionsSelectedIndex = min(
                        browserState.suggestionsSelectedIndex + 1,
                        browserState.suggestions.count - 1
                    )
                }
            },
            onSuggestionsArrowUp: {
                if !browserState.suggestions.isEmpty {
                    browserState.suggestionsSelectedIndex = max(browserState.suggestionsSelectedIndex - 1, 0)
                }
            },
            onSuggestionsEscape: {
                browserState.dismissSuggestionsPanel()
            }
        )
        .frame(maxWidth: 660)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: searchText) { _, _ in
            if isAddressBarFocused { browserState.scheduleSuggestionsRefresh() }
        }
        .onPreferenceChange(AddressBarHeightPreferenceKey.self) { height in
            if height > 0 { addressBarHeight = height }
        }
    }

    @ViewBuilder
    private var heroFloatingSuggestionsPanel: some View {
        if isAddressBarFocused && browserState.shouldShowSuggestionsPanel {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: heroSuggestionsTopInset)
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    Spacer(minLength: 0).allowsHitTesting(false)
                    AddressBarSuggestionsView(
                        suggestions: browserState.suggestions,
                        selectedIndex: browserState.suggestionsSelectedIndex,
                        isLoading: browserState.suggestionsIsLoading,
                        glassEnabled: glassEnabled,
                        toolbarMaterial: glassEnabled ? .ultraThinMaterial : .regularMaterial,
                        barCornerRadius: 18,
                        maxWidth: 660,
                        onSelect: { suggestion in
                            browserState.selectSuggestion(suggestion)
                        },
                        onDismiss: {
                            browserState.dismissSuggestionsPanel()
                        }
                    )
                    .frame(maxWidth: 660, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0).allowsHitTesting(false)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .top)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.14), value: browserState.shouldShowSuggestionsPanel)
        }
    }

    private var heroSuggestionsTopInset: CGFloat {
        addressBarHeight + 6
    }

    @ViewBuilder
    private var statusAffordanceRow: some View {
        VStack(alignment: .center, spacing: 10) {
            if showInstanceNotDetected {
                instanceNotDetectedBanner
            }

            if let errorMsg = searchErrorMessage {
                homeErrorBanner(errorMsg)
            }

            if showEnableAIToolsPrompt {
                aiToolsPrompt
            }

            if localAIChatEnabled {
                localAIChatButton
            }
        }
    }

    private func homeErrorBanner(_ errorMsg: String) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(errorMsg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("Open Settings") { onOpenSettings() }
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Dismiss") { onDismissError() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            glassEnabled ? .ultraThinMaterial : .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 0.6)
        )
    }

    private var instanceNotDetectedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)

            Text(Localization.string("home_instance_not_detected"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Button(Localization.string("open_settings")) {
                onOpenSettings()
            }
            .font(.caption.bold())
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.22), lineWidth: 0.6)
        )
    }

    private var aiToolsPrompt: some View {
        HStack(spacing: 8) {
            Text("The on-device AI can search the web for you using tools (via your private SearXNG).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button("Enable") { onEnableAITools() }
                .font(.caption.bold())
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Later") { onLaterAITools() }
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
    }

    private var localAIChatButton: some View {
        Button {
            onOpenLocalAIChat()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                Text("Local AI Chat")
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(.primary.opacity(0.95))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                glassEnabled ? .thinMaterial : .regularMaterial,
                in: Capsule()
            )
            .glassEffect(glassEnabled ? .regular.interactive() : .clear, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        AdaptiveChrome.border(colorScheme, dark: glassEnabled ? 0.12 : 0.08),
                        lineWidth: 0.7
                    )
            )
            .shadow(
                color: AdaptiveChrome.shadow(colorScheme, darkOpacity: glassEnabled ? 0.12 : 0.06),
                radius: 6,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .help("Open private on-device chat. Works great with or without a prior search (⌘⌥A).")
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    private func revealHero() {
        guard !reduceMotion else {
            heroRevealed = true
            return
        }
        withAnimation(.easeOut(duration: 0.42)) {
            heroRevealed = true
        }
    }
}

private extension View {
    func heroReveal(_ revealed: Bool, reduceMotion: Bool, delay: Double) -> some View {
        modifier(HomeHeroRevealModifier(revealed: revealed, reduceMotion: reduceMotion, delay: delay))
    }
}

private struct HomeHeroRevealModifier: ViewModifier {
    let revealed: Bool
    let reduceMotion: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (revealed ? 0 : 14))
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.42).delay(delay),
                value: revealed
            )
    }
}