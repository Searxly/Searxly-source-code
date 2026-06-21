//
//  NoSearxInstancesView.swift
//  Searxly
//
//  Small dedicated view for the "no private SearXNG instance configured" state.
//  Extracted from ContentView during the size reduction effort.
//  Can be reused in other contexts (home status row already handles a lighter version).

import SwiftUI

struct NoSearxInstancesView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
            Text(Localization.string("no_instance_configured"))
                .font(.title3.weight(.semibold))
            Text(Localization.string("no_instance_message"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button(Localization.string("open_settings")) {
                onOpenSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}