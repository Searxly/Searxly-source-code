//
//  SuggestionRowView.swift
//  Searxly
//
//  Compact row for a single address-bar suggestion.
//

import SwiftUI

enum SuggestionRowPosition {
    case only
    case first
    case middle
    case last
}

struct SuggestionRowView: View {
    let suggestion: AddressSuggestion
    let isSelected: Bool
    let glassEnabled: Bool
    let position: SuggestionRowPosition
    let panelCornerRadius: CGFloat

    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Outer corners align with the panel inset; inner corners stay soft between stacked rows.
    private var outerRadius: CGFloat {
        max(9, panelCornerRadius - 3)
    }

    private var innerRadius: CGFloat { 5 }

    private var icon: some View {
        Group {
            if suggestion.showsFavicon, let url = suggestion.url {
                FaviconView(
                    pageURL: url,
                    size: 18,
                    cornerRadius: 4,
                    loadRemote: faviconLoadRemote
                )
            } else if suggestion.action == .searchQuery {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
        }
    }

    private var faviconLoadRemote: Bool {
        if suggestion.isFromHistory {
            return PrivacyManager.shared.historyEnabled
        }
        return true
    }

    private var sourceLabel: String? {
        if suggestion.isFromHistory { return "History" }
        if suggestion.isFromBookmarks { return "Bookmark" }
        if suggestion.isRemoteSearch { return nil }
        if suggestion.isStatic { return nil }
        if suggestion.action == .navigateURL && !suggestion.isFromHistory && !suggestion.isFromBookmarks {
            return "Go"
        }
        return nil
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                icon

                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.title)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(suggestion.subtitle)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if let label = sourceLabel {
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.05))
                        )
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background {
                if isSelected {
                    selectionShape
                        .fill(AdaptiveChrome.fill(colorScheme, dark: glassEnabled ? 0.10 : 0.08, light: 0.07))
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(selectionShape)
    }

    private var selectionShape: UnevenRoundedRectangle {
        switch position {
        case .only:
            UnevenRoundedRectangle(
                topLeadingRadius: outerRadius,
                bottomLeadingRadius: outerRadius,
                bottomTrailingRadius: outerRadius,
                topTrailingRadius: outerRadius,
                style: .continuous
            )
        case .first:
            UnevenRoundedRectangle(
                topLeadingRadius: outerRadius,
                bottomLeadingRadius: innerRadius,
                bottomTrailingRadius: innerRadius,
                topTrailingRadius: outerRadius,
                style: .continuous
            )
        case .middle:
            UnevenRoundedRectangle(
                topLeadingRadius: innerRadius,
                bottomLeadingRadius: innerRadius,
                bottomTrailingRadius: innerRadius,
                topTrailingRadius: innerRadius,
                style: .continuous
            )
        case .last:
            UnevenRoundedRectangle(
                topLeadingRadius: innerRadius,
                bottomLeadingRadius: outerRadius,
                bottomTrailingRadius: outerRadius,
                topTrailingRadius: innerRadius,
                style: .continuous
            )
        }
    }
}