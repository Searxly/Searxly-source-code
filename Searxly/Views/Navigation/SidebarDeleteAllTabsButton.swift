//
//  SidebarDeleteAllTabsButton.swift
//  Searxly
//
//  Compact "Delete all tabs" action button for the left sidebar.
//  Placed immediately above the auto-hibernate timer indicator (when expanded).
//  Designed to be minimal, non-destructive in appearance until tapped, and consistent
//  with the subtle lower-sidebar typography (small secondary text + SF Symbol).
//

import SwiftUI

struct SidebarDeleteAllTabsButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("Delete all tabs")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 3)
            .background(
                isHovered
                    ? AdaptiveChrome.fill(colorScheme, dark: 0.06)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            DispatchQueue.main.async {
                isHovered = hovering
            }
        }
        .help("Close every tab and start fresh (keeps one new tab)")
    }
}
