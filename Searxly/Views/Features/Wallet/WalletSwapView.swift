//
//  WalletSwapView.swift
//  Searxly
//
//  In-wallet token swaps on Base via the 0x Swap API. Requires a 0x API key (Settings).
//

import SwiftUI

struct WalletSwapView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var wallet = WalletManager.shared

    @State private var sellID = "ETH"
    @State private var buyID = "SEARXLY"
    @State private var amountText = ""
    @State private var quote: SwapQuote?
    @State private var loadingQuote = false
    @State private var error = ""
    @State private var pin = ""
    @State private var pinError = false
    @State private var swapping = false
    @State private var resultHash: String?

    private var sellToken: WalletToken? { wallet.tokens.first { $0.id == sellID } }
    private var buyToken: WalletToken? { wallet.tokens.first { $0.id == buyID } }
    private var amount: Decimal? {
        // Parse straight into Decimal to avoid float rounding error in the sell amount.
        let raw = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let d = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")), d > 0 else { return nil }
        return d
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) { content.padding(20) }
        }
        .frame(width: 380)
        .frame(minHeight: 460, maxHeight: 640)
        .background(WalletTheme.canvas)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            SearxlyWalletBadge(size: 30, cornerRadius: 8, glassEnabled: false)
            Text("Swap").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WalletTheme.textSecondary).frame(width: 30, height: 30)
                    .background(WalletTheme.surface, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if let hash = resultHash {
            successView(hash)
        } else {
            VStack(spacing: 14) {
                if !swapsReady { swapSetupBanner }
                tokenPicker(title: "From", selection: $sellID)
                amountField
                Image(systemName: "arrow.down").font(.system(size: 13)).foregroundStyle(Color(white: 0.4))
                tokenPicker(title: "To", selection: $buyID)

                if let q = quote {
                    quoteBox(q)
                }
                if !error.isEmpty {
                    Text(error).font(.system(size: 11)).foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
                        .multilineTextAlignment(.center)
                }

                if quote == nil {
                    actionButton(loadingQuote ? "Getting quote…" : "Get Quote",
                                 enabled: amount != nil && sellID != buyID && !loadingQuote) {
                        Task { await fetchQuote() }
                    }
                } else {
                    authSection
                }
            }
        }
    }

    private var swapsReady: Bool {
        // The gateway supplies the 0x key server-side, so a user key is no longer required —
        // only the Swaps toggle needs to be on (off by default for privacy).
        WalletFeatures.swaps && (!WalletFeatures.zeroExAPIKey.isEmpty || SearxlyGateway.isConfigured)
    }

    /// Shown when swaps aren't set up yet, so the screen isn't a dead end.
    private var swapSetupBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "key.horizontal").font(.system(size: 14)).foregroundStyle(WalletTheme.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text("Turn on swaps").font(.system(size: 12, weight: .semibold)).foregroundStyle(WalletTheme.textPrimary)
                Text(SearxlyGateway.isConfigured
                     ? "Open Settings → Wallet → Wallet Features and turn on **Swaps**. No API key needed."
                     : "Swaps use the 0x aggregator and need a free API key. Open Settings → Wallet → Wallet Features, turn on **Swaps**, and paste a 0x key.")
                    .font(.system(size: 11)).foregroundStyle(WalletTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(WalletTheme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WalletTheme.warning.opacity(0.3), lineWidth: 1))
    }

    private func tokenPicker(title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(white: 0.4))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(wallet.visibleTokens) { token in
                        Button { selection.wrappedValue = token.id; quote = nil; error = "" } label: {
                            HStack(spacing: 6) {
                                TokenIconView(token: token, size: 18)
                                Text(token.symbol).font(.system(size: 12, weight: selection.wrappedValue == token.id ? .semibold : .regular))
                                    .foregroundStyle(selection.wrappedValue == token.id ? .white : Color(white: 0.45))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(selection.wrappedValue == token.id ? Color(white: 0.18) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
            }
            .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var amountField: some View {
        HStack {
            TextField("0.00", text: $amountText)
                .textFieldStyle(.plain).font(.system(size: 15, weight: .medium, design: .monospaced)).foregroundStyle(.white)
                .onChange(of: amountText) { _, _ in quote = nil }
            Text(sellToken?.symbol ?? "").font(.system(size: 12)).foregroundStyle(Color(white: 0.4))
        }
        .padding(12).background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 9))
    }

    private func quoteBox(_ q: SwapQuote) -> some View {
        VStack(spacing: 0) {
            row("You receive", "\(q.buyAmountDisplay) \(q.buyToken.symbol)")
            Divider().opacity(0.08)
            row("Minimum received", "\(q.minBuyAmountDisplay) \(q.buyToken.symbol)")
            if q.needsAllowanceTo != nil {
                Divider().opacity(0.08)
                row("Note", "Approval tx first")
            }
        }
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var authSection: some View {
        VStack(spacing: 10) {
            if swapping {
                ProgressView().padding(.vertical, 12)
                Text("Submitting swap…").font(.system(size: 11)).foregroundStyle(Color(white: 0.4))
            } else {
                if wallet.biometricUnlockEnabled && wallet.biometricAvailable {
                    actionButton("Authorize with \(WalletBiometric.label)", enabled: true) {
                        Task {
                            if let p = await wallet.authorizeSigningWithBiometrics(reason: "Authorize swap") { await doSwap(pin: p) }
                        }
                    }
                    Text("or enter your PIN").font(.system(size: 11)).foregroundStyle(Color(white: 0.4))
                } else {
                    Text("Enter your PIN to authorize").font(.system(size: 12)).foregroundStyle(Color(white: 0.4))
                }
                HStack(spacing: 12) {
                    ForEach(0..<WalletConfig.pinLength, id: \.self) { i in
                        Circle().fill(i < pin.count ? Color.white : Color(white: 0.2)).frame(width: 11, height: 11)
                    }
                }
                if pinError { Text("Incorrect PIN").font(.system(size: 12)).foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35)) }
                PINKeypad(pin: $pin, maxLength: WalletConfig.pinLength) {
                    guard wallet.attemptPIN(pin) else { pinError = true; pin = ""; return }
                    let p = pin; pin = ""
                    Task { await doSwap(pin: p) }
                }
                .frame(maxWidth: 220)
                Button("Edit swap") { quote = nil }.font(.system(size: 11)).foregroundStyle(Color(white: 0.4)).buttonStyle(.plain)
            }
        }
    }

    private func successView(_ hash: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.white).padding(.top, 30)
            Text("Swap submitted").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            Button { if let u = URL(string: wallet.explorerTxURL(hash)) { NSWorkspace.shared.open(u) } } label: {
                Text("View on \(wallet.activeChain.explorerName)").font(.system(size: 12)).foregroundStyle(Color(white: 0.6))
            }.buttonStyle(.plain)
            actionButton("Done", enabled: true) { dismiss() }
        }
    }

    private func actionButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? .black : Color(white: 0.3))
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(enabled ? Color.white : Color(white: 0.12), in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }

    private func row(_ l: String, _ v: String) -> some View {
        HStack {
            Text(l).font(.system(size: 12)).foregroundStyle(Color(white: 0.4))
            Spacer()
            Text(v).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.white)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func fetchQuote() async {
        guard let sell = sellToken, let buy = buyToken, let amt = amount, let taker = wallet.activeAddress else { return }
        loadingQuote = true; error = ""
        let result = await WalletSwap.quote(sell: sell, buy: buy, sellAmount: amt, taker: taker,
                                            chainId: wallet.activeChain.id)
        loadingQuote = false
        switch result {
        case .success(let q): quote = q
        case .failure(let e): error = e.localizedDescription
        }
    }

    private func doSwap(pin: String) async {
        guard let q = quote else { return }
        swapping = true; error = ""
        let result = await wallet.executeSwap(quote: q, pin: pin)
        swapping = false
        if let hash = result.hash { resultHash = hash }
        else { error = result.error ?? "Swap failed"; pinError = false }
    }
}
