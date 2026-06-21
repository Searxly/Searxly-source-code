//
//  WalletWindowHost.swift
//  Searxly
//
//  Presents the wallet as a single fixed-size, centered overlay card (not a macOS sheet) with a
//  dimmed backdrop. One size only — clean and predictable, Phantom-style.
//

import SwiftUI

struct WalletWindowHost: View {
    @Bindable var browserState: BrowserState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if browserState.showingWallet {
                    // Dimmed backdrop — click outside (or Esc) to dismiss.
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { close() }

                    WalletPanelView(onClose: close, onOpenURL: openURL)
                        .frame(width: min(524, geo.size.width - 40),
                               height: min(728, geo.size.height - 40))
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .shadow(color: .black.opacity(0.55), radius: 48, y: 20)
                        .transition(.scale(scale: 0.97).combined(with: .opacity))
                        .onExitCommand { close() }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.spring(response: 0.34, dampingFraction: 0.9), value: browserState.showingWallet)
        }
        .ignoresSafeArea()
    }

    private func close() { browserState.showingWallet = false }

    /// Opens a Discover dApp in a new browser tab, then closes the wallet panel.
    private func openURL(_ url: String) {
        browserState.openResultsInTabs(urls: [url])
        close()
    }
}
