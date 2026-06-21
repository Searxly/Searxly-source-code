//
//  WalletPanelView.swift
//  Searxly
//
//  Root wallet view — a flat, calm, Phantom-style home. One continuous dark canvas, no dividers,
//  no bands, no borders. The home is: a single header row (account + actions), a centered balance,
//  four round action buttons, and a clean uniform token list. Send / Receive push in with a back
//  button; a small floating segmented control at the bottom switches Home ↔ Activity.
//

import SwiftUI
import Combine

struct WalletPanelView: View {
    var onClose: () -> Void
    /// Opens a URL in the browser (used by the Discover tab). Default no-op for previews.
    var onOpenURL: (String) -> Void = { _ in }

    @State private var wallet = WalletManager.shared
    @State private var activeTab: WalletTab = .portfolio
    @State private var showSwap = false
    @State private var showAccounts = false
    @State private var showSettings = false

    enum WalletTab { case portfolio, send, receive, activity, discover }

    var body: some View {
        Group {
            switch wallet.unlockState {
            case .notSetup: WalletSetupView(onClose: onClose)
            case .locked:   WalletLockView(onClose: onClose)
            case .unlocked: unlockedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WalletTheme.canvas)
        .preferredColorScheme(.dark)
    }

    // MARK: - Unlocked content

    private var unlockedContent: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch activeTab {
                case .portfolio:
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            balanceBlock
                            homeActionRow
                            WalletPortfolioView()
                        }
                    }
                case .send:      WalletSendView()
                case .receive:   WalletReceiveView()
                case .activity:  WalletActivityView()
                case .discover:  WalletDiscoverView(onOpen: onOpenURL)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom nav lives only on the "destinations"; Send/Receive use the header back arrow.
            if activeTab == .portfolio || activeTab == .activity || activeTab == .discover { bottomNav }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSwap) { WalletSwapView() }
        .sheet(isPresented: $showAccounts) { WalletAccountsSheet(onClose: { showAccounts = false }) }
        .sheet(isPresented: $showSettings) { walletSettingsSheet }
        .onAppear { wallet.registerActivity() }
        .onChange(of: activeTab) { _, _ in wallet.registerActivity() }
    }

    // MARK: - Header (one row: account / back · settings · lock · close)

    private var header: some View {
        HStack(spacing: 10) {
            if activeTab == .send {
                backTitle("Send")
            } else if activeTab == .receive {
                backTitle("Receive")
            } else {
                accountPill
            }

            Spacer()

            if activeTab == .portfolio || activeTab == .activity { chainChip }
            headerIconButton("lock", help: "Lock wallet") { wallet.lock() }
            headerIconButton("xmark", help: "Close") { onClose() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    /// Monochrome network switcher. Same HD address on every chain — switching only changes the
    /// RPC, native token, explorer, and prices. (Brand: monochrome; no per-chain colors.)
    private var chainChip: some View {
        Menu {
            ForEach(WalletChain.all) { chain in
                Button { wallet.switchChain(to: chain) } label: {
                    if chain.id == wallet.activeChain.id {
                        Label(chain.name, systemImage: "checkmark")
                    } else {
                        Text(chain.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 10, weight: .semibold))
                Text(wallet.activeChain.shortName)
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(WalletTheme.textTertiary)
            }
            .foregroundStyle(WalletTheme.textSecondary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(WalletTheme.surface, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Switch network")
    }

    /// Flat tappable account selector — avatar, label, short address, chevron. No pill, no border.
    private var accountPill: some View {
        Button { showAccounts = true } label: {
            HStack(spacing: 9) {
                AccountAvatar(address: wallet.activeAccount?.address ?? "", size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(wallet.activeAccount?.label ?? "Account")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WalletTheme.textPrimary)
                    Text(wallet.activeAccount?.shortAddress ?? "")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(WalletTheme.textTertiary)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(WalletTheme.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Back affordance shown on the Send / Receive screens.
    private func backTitle(_ title: String) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.14)) { activeTab = .portfolio } } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WalletTheme.textSecondary)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WalletTheme.textPrimary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func headerIconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WalletTheme.textSecondary)
                .frame(width: 30, height: 30)
                .background(WalletTheme.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Balance (centered hero, no band / label / chip)

    private var balanceBlock: some View {
        VStack(spacing: 6) {
            if wallet.isFetchingPrices {
                ProgressView().scaleEffect(0.7).padding(.vertical, 22)
            } else {
                Text(wallet.formatFiat(wallet.totalPortfolioUSD))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .background(balanceGlow)

                if wallet.hasHoldings {
                    let change = wallet.portfolioChange24h
                    if change != 0 {
                        let tone = change >= 0 ? WalletTheme.positive : WalletTheme.negative
                        HStack(spacing: 3) {
                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text(String(format: "%.2f%%", abs(change)))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(tone)
                    }
                }

                portfolioMiniChart
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    /// Compact portfolio-value sparkline. Built from on-device snapshots only (no network); hidden
    /// until a real, non-flat-zero series has accumulated.
    @ViewBuilder
    private var portfolioMiniChart: some View {
        let series = wallet.portfolioSeries
        if series.count >= 2, (series.map(\.usd).max() ?? 0) > 0 {
            WalletLineChart(points: series.map { PricePoint(t: $0.t, v: $0.usd) }, compact: true)
                .frame(height: 44)
                .padding(.horizontal, 28)
                .padding(.top, 14)
        }
    }

    /// A soft white halo behind the balance number (Phantom-style hero glow).
    private var balanceGlow: some View {
        RadialGradient(
            gradient: Gradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.04), .clear]),
            center: .center, startRadius: 2, endRadius: 120
        )
        .frame(width: 300, height: 150)
        .blur(radius: 22)
        .allowsHitTesting(false)
    }

    // MARK: - Quick actions (Receive / Send / Swap / Buy)

    private var homeActionRow: some View {
        // Watch-only accounts have no key — Send and Swap are disabled (Receive/Buy still work).
        let canSign = !wallet.activeAccountIsWatchOnly
        return HStack(spacing: 0) {
            actionButton("Receive", icon: "arrow.down") { withAnimation(.easeInOut(duration: 0.14)) { activeTab = .receive } }
            actionButton("Send", icon: "arrow.up", enabled: canSign) { withAnimation(.easeInOut(duration: 0.14)) { activeTab = .send } }
            actionButton("Swap", icon: "arrow.2.squarepath", enabled: canSign) { showSwap = true }
            actionButton("Buy", icon: "creditcard") { openBuy() }
        }
        .padding(.horizontal, 22)
        .padding(.top, 2)
        .padding(.bottom, 20)
    }

    private func actionButton(_ label: String, icon: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(WalletTheme.surfaceStrong)
                        .frame(width: 54, height: 54)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WalletTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .opacity(enabled ? 1 : 0.32)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func openBuy() {
        guard let addr = wallet.activeAddress,
              let url = URL(string: WalletConfig.onrampURL(address: addr)) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Bottom tab bar (Home · Discover · Activity · Settings)

    private var bottomNav: some View {
        HStack(spacing: 0) {
            navTab("Home", icon: "house.fill", selected: activeTab == .portfolio) {
                withAnimation(.easeInOut(duration: 0.14)) { activeTab = .portfolio }
            }
            navTab("Discover", icon: "square.grid.2x2", selected: activeTab == .discover) {
                withAnimation(.easeInOut(duration: 0.14)) { activeTab = .discover }
            }
            navTab("Activity", icon: "clock", selected: activeTab == .activity) {
                withAnimation(.easeInOut(duration: 0.14)) { activeTab = .activity }
            }
            navTab("Settings", icon: "gearshape", selected: false) { showSettings = true }
        }
        .padding(.top, 9)
        .padding(.bottom, 11)
        .overlay(alignment: .top) {
            Rectangle().fill(WalletTheme.hairline).frame(height: 0.5)
        }
    }

    private func navTab(_ label: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium))
                Text(label).font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(selected ? WalletTheme.textPrimary : WalletTheme.textTertiary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Wallet settings (presented from the header gear button)

    private var walletSettingsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Wallet Settings").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Button { showSettings = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(WalletTheme.surface, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            ScrollView { WalletSettingsSection().padding(20) }
        }
        .frame(width: 560, height: 680)
        .background(WalletTheme.canvas)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Lock screen

private struct WalletLockView: View {
    var onClose: () -> Void
    @State private var pin = ""
    @State private var showError = false
    @State private var isRecovering = false
    @State private var recoveryCode = ""
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var recoveryError = false
    @State private var wallet = WalletManager.shared
    @State private var now = Date()
    @State private var showDelete = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var lockCountdownText: String {
        let secs = Int(ceil(wallet.pinLockRemaining))
        if secs >= 60 { return "\(secs / 60)m \(secs % 60)s" }
        return "\(secs)s"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WalletTheme.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(WalletTheme.surface, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()
            if isRecovering { recoveryView } else { pinEntryView }
            Spacer()
        }
        .onReceive(ticker) { now = $0 }
    }

    private var pinEntryView: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(WalletTheme.surfaceStrong)
                        .frame(width: 64, height: 64)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(WalletTheme.textSecondary)
                }
                Text("Wallet Locked")
                    .font(.system(size: 19, weight: .semibold))
                Text("Enter your 6-digit PIN")
                    .font(.system(size: 12))
                    .foregroundStyle(WalletTheme.textTertiary)
            }

            HStack(spacing: 12) {
                ForEach(0..<WalletConfig.pinLength, id: \.self) { i in
                    Circle()
                        .fill(i < pin.count ? Color.white : WalletTheme.surfaceStrong)
                        .frame(width: 12, height: 12)
                        .animation(.spring(response: 0.18), value: pin.count)
                }
            }

            if wallet.isPINLocked {
                VStack(spacing: 3) {
                    Text("Too many attempts")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WalletTheme.warning)
                    Text("Try again in \(lockCountdownText)")
                        .font(.system(size: 11))
                        .foregroundStyle(WalletTheme.textTertiary)
                }
            } else if showError {
                Text(wallet.pinAttemptsRemaining <= 2
                     ? "Incorrect PIN · \(wallet.pinAttemptsRemaining) attempt\(wallet.pinAttemptsRemaining == 1 ? "" : "s") left"
                     : "Incorrect PIN")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WalletTheme.negative)
                    .transition(.opacity)
            }

            PINKeypad(pin: $pin, maxLength: WalletConfig.pinLength) { attemptUnlock() }
                .frame(maxWidth: 240)
                .disabled(wallet.isPINLocked)
                .opacity(wallet.isPINLocked ? 0.4 : 1)

            HStack(spacing: 16) {
                if wallet.biometricUnlockEnabled && wallet.biometricAvailable {
                    Button {
                        Task { _ = await wallet.unlockWithBiometrics() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: WalletBiometric.symbol)
                                .font(.system(size: 13))
                            Text("Unlock with \(WalletBiometric.label)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }

                Button("Use recovery code") {
                    withAnimation { isRecovering = true }
                }
                .font(.system(size: 11))
                .foregroundStyle(WalletTheme.textTertiary)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 40)
        .task {
            // Auto-present biometrics when enabled.
            if wallet.biometricUnlockEnabled && wallet.biometricAvailable {
                _ = await wallet.unlockWithBiometrics()
            }
        }
    }

    private var recoveryView: some View {
        VStack(spacing: 16) {
            Text("Recovery Code")
                .font(.system(size: 17, weight: .semibold))
            Text("Enter the recovery code you saved during setup.")
                .font(.system(size: 12))
                .foregroundStyle(WalletTheme.textTertiary)
                .multilineTextAlignment(.center)

            SecureField("Recovery code (32 characters)", text: $recoveryCode)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(12)
                .background(WalletTheme.surfaceField, in: RoundedRectangle(cornerRadius: WalletTheme.radiusField))
                .frame(maxWidth: 300)

            SecureField("New 6-digit PIN", text: $newPIN)
                .textFieldStyle(.plain)
                .padding(12)
                .background(WalletTheme.surfaceField, in: RoundedRectangle(cornerRadius: WalletTheme.radiusField))
                .frame(maxWidth: 300)

            SecureField("Confirm new PIN", text: $confirmPIN)
                .textFieldStyle(.plain)
                .padding(12)
                .background(WalletTheme.surfaceField, in: RoundedRectangle(cornerRadius: WalletTheme.radiusField))
                .frame(maxWidth: 300)

            if recoveryError {
                Text("Invalid recovery code or PIN mismatch")
                    .font(.system(size: 12))
                    .foregroundStyle(WalletTheme.negative)
            }

            HStack(spacing: 12) {
                Button("Back") { withAnimation { isRecovering = false; recoveryError = false } }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                Button("Reset PIN") { attemptRecovery() }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .controlSize(.regular)
                    .disabled(recoveryCode.count < 16 || newPIN.count != WalletConfig.pinLength || newPIN != confirmPIN)
            }

            Button("Delete Wallet & Start Fresh") {
                showDelete = true
            }
            .font(.system(size: 11))
            .foregroundStyle(WalletTheme.negative.opacity(0.7))
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(.horizontal, 40)
        .sheet(isPresented: $showDelete) {
            DeleteWalletSheet(
                requiresPIN: false,   // user is locked out without a PIN
                onCancel: { showDelete = false },
                onConfirmed: { wallet.deleteWallet(); showDelete = false }
            )
        }
    }

    private func attemptUnlock() {
        guard pin.count == WalletConfig.pinLength else { return }
        if wallet.unlock(pin: pin) {
            showError = false
        } else {
            showError = true
            pin = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showError = false }
        }
    }

    private func attemptRecovery() {
        guard newPIN == confirmPIN else { recoveryError = true; return }
        if !wallet.unlockWithRecoveryCode(recoveryCode, newPIN: newPIN) { recoveryError = true }
    }
}

// MARK: - Portfolio tab (one flat, uniform token list — SEARXLY pinned first)

private struct WalletPortfolioView: View {
    @State private var wallet = WalletManager.shared
    @State private var showAddToken = false
    @State private var detailToken: WalletToken? = nil

    /// SEARXLY first, then everything else — one consistent row style for all (no special card).
    private var orderedTokens: [WalletToken] {
        let hero = wallet.visibleTokens.filter { $0.symbol == "SEARXLY" }
        let rest = wallet.visibleTokens.filter { $0.symbol != "SEARXLY" }
        return hero + rest
    }

    var body: some View {
        VStack(spacing: 2) {
            if !wallet.hasHoldings {
                Text("Your wallet is empty — tap Receive to get your address.")
                    .font(.system(size: 12))
                    .foregroundStyle(WalletTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 6)
            }

            ForEach(orderedTokens) { token in
                tokenRow(token)
            }

            if !wallet.hiddenTokenIDs.isEmpty {
                Button { wallet.unhideAllTokens() } label: {
                    Text("Show \(wallet.hiddenTokenIDs.count) hidden token\(wallet.hiddenTokenIDs.count == 1 ? "" : "s")")
                        .font(.system(size: 11)).foregroundStyle(WalletTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }

            addCoinButton
        }
        .padding(.top, 2)
        .padding(.bottom, 10)
        .sheet(isPresented: $showAddToken) { AddTokenSheet() }
        .sheet(item: $detailToken) { token in TokenDetailView(token: token) }
    }

    private var addCoinButton: some View {
        Button { showAddToken = true } label: {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(WalletTheme.surface)
                        .frame(width: 40, height: 40)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WalletTheme.textSecondary)
                }
                Text("Add another coin")
                    .font(.system(size: 14))
                    .foregroundStyle(WalletTheme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    /// A clean, flat token row. Tap → detail; right-click → copy / hide / remove (kept off the row to
    /// reduce visual noise, Phantom-style).
    @ViewBuilder
    private func tokenRow(_ token: WalletToken) -> some View {
        Button { detailToken = token } label: {
            HStack(spacing: 13) {
                TokenIconView(token: token, size: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(token.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WalletTheme.textPrimary)
                    Text("\(token.formattedBalance) \(token.symbol)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(WalletTheme.textTertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(wallet.formatFiat(token.usdValue))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WalletTheme.textPrimary)
                        .monospacedDigit()
                    if token.balance > 0 && token.change24h != 0 {
                        Text(String(format: "%+.2f%%", token.change24h))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(token.change24h >= 0 ? WalletTheme.positive : WalletTheme.negative)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let addr = token.contractAddress {
                Button("Copy contract address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(addr, forType: .string)
                }
            }
            if token.symbol != "SEARXLY" {
                Button { WalletManager.shared.hideToken(id: token.id) } label: {
                    Label("Hide token", systemImage: "eye.slash")
                }
            }
            if token.isCustom {
                Divider()
                Button(role: .destructive) {
                    WalletManager.shared.removeCustomToken(id: token.id)
                } label: {
                    Label("Remove token", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - PIN Keypad (shared across setup, lock, send confirm)

struct PINKeypad: View {
    @Binding var pin: String
    let maxLength: Int
    let onComplete: () -> Void

    private let keys: [[String]] = [
        ["1","2","3"],
        ["4","5","6"],
        ["7","8","9"],
        ["","0","⌫"]
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { key in keyButton(key) }
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        if key.isEmpty {
            Color.clear.frame(width: 64, height: 44)
        } else {
            Button {
                if key == "⌫" {
                    if !pin.isEmpty { pin.removeLast() }
                } else if pin.count < maxLength {
                    pin.append(key)
                    if pin.count == maxLength {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onComplete() }
                    }
                }
            } label: {
                Text(key)
                    .font(.system(size: key == "⌫" ? 16 : 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 44)
                    .background(WalletTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}
