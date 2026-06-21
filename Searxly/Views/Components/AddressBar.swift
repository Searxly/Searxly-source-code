//
//  AddressBar.swift
//  Searxly
//
//  Plain unified address/search bar (the visual + TextField part).
//  Suggestions feature (including search history, bookmarks, statics) has been DELETED per user request.
//  No dropdowns are shown or updated from the address bar (home or header).
//  The bar is a simple focused TextField. Legacy suggestion params in init are ignored.
//  Submit (Return) or the parent decides what to do with the text.
//  Styling matches the rest of the app (glass, focus ring, scale, shadow) with simple hero vs slim sizing.

import SwiftUI

struct AddressBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Slim header bar bounds in the parent `mainColumn` coordinate space (for anchoring suggestions).
struct AddressBarFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

struct AddressBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool

    let showingWebContent: Bool
    let glassEnabled: Bool
    let toolbarMaterial: Material
    let onSubmit: () -> Void

    /// Larger, more prominent metrics + positioning for the centered bar on pure home/new tab.
    var isHero: Bool = false

    // Suggestion keyboard hooks are no longer used (suggestions feature DELETED per user request).
    // Params kept with defaults for any remaining call sites during cleanup; they are ignored.
    private let onSuggestionsArrowDown: (() -> Void)?
    private let onSuggestionsArrowUp: (() -> Void)?
    private let onSuggestionsEscape: (() -> Void)?

    init(
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        showingWebContent: Bool,
        glassEnabled: Bool,
        toolbarMaterial: Material,
        history: [HistoryItem] = [],
        bookmarks: [BookmarkItem] = [],
        onSubmit: @escaping () -> Void,
        isHero: Bool = false,
        isCompact: Bool = false,
        suppressSuggestions: Bool = false,
        drawsOwnSuggestionsOverlay: Bool = true,
        isSuggestionsPanelHoisted: Binding<Bool> = .constant(false),
        hoistedSuggestionsPanelWidth: Binding<CGFloat> = .constant(520),
        hoistedSelectedIndex: Binding<Int> = .constant(0),
        isSuggestionsPanelOpen: Bool = false,
        isSuggestionsPanelVisible: Binding<Bool> = .constant(false),
        suggestionsPanelFrame: Binding<CGRect> = .constant(.zero),
        suggestionsSelectedIndex: Binding<Int> = .constant(0),
        onSuggestionsArrowDown: (() -> Void)? = nil,
        onSuggestionsArrowUp: (() -> Void)? = nil,
        onSuggestionsEscape: (() -> Void)? = nil
    ) {
        self._text = text
        self._isFocused = isFocused
        self.showingWebContent = showingWebContent
        self.glassEnabled = glassEnabled
        self.toolbarMaterial = toolbarMaterial
        self.onSubmit = onSubmit
        self.isHero = isHero

        self.onSuggestionsArrowDown = onSuggestionsArrowDown
        self.onSuggestionsArrowUp = onSuggestionsArrowUp
        self.onSuggestionsEscape = onSuggestionsEscape
    }

    // MARK: - Sizing (hero = big centered on home; slim when web content or in header)

    private var isBrowserBar: Bool { showingWebContent && !isHero }

    @Environment(\.colorScheme) private var colorScheme

    private var verticalPadding: CGFloat {
        if isHero { return 14 }
        if isBrowserBar { return 5 }
        return 7
    }

    private var horizontalPadding: CGFloat {
        if isHero { return 18 }
        if isBrowserBar { return 10 }
        return 12
    }

    private var cornerRadius: CGFloat {
        if isHero { return 18 }
        if isBrowserBar { return 11 }
        return 12
    }

    private var iconSize: CGFloat {
        if isHero { return 17 }
        if isBrowserBar { return 12 }
        return 13
    }

    private var fontSize: CGFloat {
        if isHero { return 16.5 }
        if isBrowserBar { return 13.5 }
        return 14
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: showingWebContent ? "globe" : "magnifyingglass")
                .foregroundStyle(.secondary.opacity(isHero ? 1.0 : 0.9))
                .font(.system(size: iconSize, weight: .regular))

            TextField("Search or enter address", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize, weight: .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .focused($isFocused)
                .onSubmit {
                    onSubmit()
                }
                // Keyboard support for suggestions (arrows/escape) when parent provides hooks.
                // .down / .up update parent's selectedIndex (which drives highlight in the dropdown).
                // .escape hides the panel via parent.
                .onKeyPress(.downArrow) {
                    onSuggestionsArrowDown?()
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    onSuggestionsArrowUp?()
                    return .handled
                }
                .onKeyPress(.escape) {
                    onSuggestionsEscape?()
                    return .handled
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, horizontalPadding)
        .background(
            toolbarMaterial,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .background {
            if isHero && glassEnabled {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AdaptiveChrome.fill(colorScheme, dark: 0.025, light: 0.018))
            }
        }
        .glassEffect(
            glassEnabled
                ? (isHero ? .regular : .regular.interactive())
                : .clear,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    heroBorderColor,
                    lineWidth: isFocused ? (isHero ? 1.15 : 0.9) : (isHero ? 0.65 : 0.5)
                )
        )
        .overlay {
            if isHero && isFocused && glassEnabled {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(colorScheme == .dark ? 0.2 : 0.14),
                        lineWidth: 1.4
                    )
                    .blur(radius: 0.4)
                    .allowsHitTesting(false)
            }
        }
        .shadow(
            color: AdaptiveChrome.shadow(
                colorScheme,
                darkOpacity: isHero ? (isFocused ? 0.16 : 0.1) : (isFocused ? 0.08 : 0.04)
            ),
            radius: isHero ? (isFocused ? 14 : 10) : (isFocused ? 3 : 1),
            x: 0,
            y: isHero ? (isFocused ? 5 : 3) : 1
        )
        .animation(.easeOut(duration: 0.12), value: isFocused)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .simultaneousGesture(
            TapGesture().onEnded {
                guard isHero else { return }
                isFocused = true
            },
            including: isHero ? .all : .subviews
        )
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: AddressBarHeightPreferenceKey.self, value: proxy.size.height)
                    .preference(
                        key: AddressBarFramePreferenceKey.self,
                        value: isHero ? .zero : proxy.frame(in: .named("mainColumn"))
                    )
            }
        }
    }

    private var heroBorderColor: Color {
        if isHero {
            return AdaptiveChrome.border(
                colorScheme,
                dark: isFocused ? (glassEnabled ? 0.24 : 0.18) : (glassEnabled ? 0.1 : 0.07),
                light: isFocused ? 0.16 : 0.08
            )
        }
        return Color.primary.opacity(isFocused ? 0.12 : 0.06)
    }
}
