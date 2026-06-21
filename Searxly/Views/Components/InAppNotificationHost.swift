//
//  InAppNotificationHost.swift
//  Searxly
//
//  Container / stack for the current in-app notifications.
//  - Positions them top-trailing over the browser content (never over sidebar or address bar chrome).
//  - Handles the stack layout (newest visually "on top" via reverse order or z-index feel).
//  - Kept as its own file so the notification system doesn't live in one monolithic place.
//  - Rendered at root when there are items (manager only populates in-app toasts when on browser, except dev tests which force for verification).
//

import SwiftUI

struct InAppNotificationHost: View {
    let notifications: [AppNotification]
    let glassEnabled: Bool
    let toolbarMaterial: Material

    var onDismiss: (UUID) -> Void
    var onInteract: (AppNotification) -> Void = { _ in }

    var body: some View {
        // We reverse so the most recent appears "highest" visually (last in VStack is bottom-most in stack,
        // but for notifications newest-on-top we put newest first in the visual stack by reversing here).
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(notifications.reversed()) { notification in
                InAppNotificationBanner(
                    notification: notification,
                    glassEnabled: glassEnabled,
                    toolbarMaterial: toolbarMaterial,
                    onDismiss: {
                        onDismiss(notification.id)
                    },
                    onInteract: {
                        onInteract(notification)
                    }
                )
            }
        }
        .frame(maxWidth: 340, alignment: .trailing)
        // The host itself doesn't add extra chrome; the individual banners are the glass elements.
    }
}

#Preview {
    ZStack(alignment: .topTrailing) {
        Color.black.opacity(0.9)
            .frame(width: 520, height: 420)

        InAppNotificationHost(
            notifications: [
                AppNotification(title: "Mention on X", body: "@grok just posted about private search engines.", source: "X", iconSystemName: "at.circle.fill"),
                AppNotification(title: "Search alert", body: "New results available for your saved query.", source: "Searxly", iconSystemName: "magnifyingglass.circle.fill")
            ],
            glassEnabled: true,
            toolbarMaterial: .regular
        ) { _ in
            // dismiss
        }
        .padding(.top, 60)
        .padding(.trailing, 16)
    }
}