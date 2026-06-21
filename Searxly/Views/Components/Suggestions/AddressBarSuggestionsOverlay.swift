//
//  AddressBarSuggestionsOverlay.swift
//  Searxly
//
//  Reusable suggestions dropdown attachment for hero and slim address bars.
//

import SwiftUI

/// Attaches the suggestions panel below an address bar (hero overlay or slim hoisted layout).
struct AddressBarSuggestionsOverlay: View {
    @Bindable var browserState: BrowserState
    let isFocused: Bool
    let glassEnabled: Bool
    let toolbarMaterial: Material
    let barCornerRadius: CGFloat
    let maxWidth: CGFloat
    let barHeight: CGFloat
    var verticalOffset: CGFloat = 6
    var leadingOffset: CGFloat = 0

    private var isVisible: Bool {
        isFocused && browserState.shouldShowSuggestionsPanel
    }

    var body: some View {
        if isVisible {
            AddressBarSuggestionsView(
                suggestions: browserState.suggestions,
                selectedIndex: browserState.suggestionsSelectedIndex,
                isLoading: browserState.suggestionsIsLoading,
                glassEnabled: glassEnabled,
                toolbarMaterial: toolbarMaterial,
                barCornerRadius: barCornerRadius,
                maxWidth: maxWidth,
                onSelect: { suggestion in
                    browserState.selectSuggestion(suggestion)
                },
                onDismiss: {
                    browserState.dismissSuggestionsPanel()
                }
            )
            .frame(maxWidth: maxWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .offset(x: leadingOffset, y: barHeight + verticalOffset)
            .allowsHitTesting(true)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.easeOut(duration: 0.14), value: isVisible)
        }
    }
}

