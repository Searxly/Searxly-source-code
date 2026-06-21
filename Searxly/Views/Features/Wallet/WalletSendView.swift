//
//  WalletSendView.swift
//  Searxly
//

import SwiftUI

struct WalletSendView: View {
    @State private var wallet = WalletManager.shared
    @State private var toAddress = ""
    @State private var amountText = ""
    @State private var selectedTokenID = "SEARXLY"
    @State private var sendError = ""
    @State private var isSending = false
    @State private var showConfirm = false
    @State private var pin = ""
    @State private var pinError = false
    @State private var sentTxHash: String? = nil
    @State private var gasSpeed: GasSpeed = WalletFeatures.defaultGasSpeed
    @State private var resolvedAddress: String? = nil   // address resolved from a name
    @State private var resolving = false
    @State private var resolveTask: Task<Void, Never>? = nil
    @State private var ackRisk = false                  // user confirmed a risky destination
    @State private var contacts = WalletContactsStore.shared
    @State private var showContacts = false
    @State private var savingContact = false
    @State private var contactLabel = ""

    private var selectedToken: WalletToken? {
        wallet.tokens.first { $0.id == selectedTokenID }
    }

    private var parsedAmount: Decimal? {
        // Parse the string straight into Decimal (NOT via Double) to avoid float rounding error
        // that would change the exact wei amount sent. Normalize a comma decimal separator.
        let raw = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let d = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")), d > 0 else { return nil }
        return d
    }

    private var looksLikeName: Bool {
        let a = toAddress.trimmingCharacters(in: .whitespaces)
        return !a.hasPrefix("0x") && a.contains(".")
    }

    /// The actual 0x address to send to: either typed directly or resolved from a name.
    private var effectiveRecipient: String? {
        let a = toAddress.trimmingCharacters(in: .whitespaces)
        if a.hasPrefix("0x") && a.count == 42 { return a }
        return resolvedAddress
    }

    /// Contract addresses the wallet knows about — used to flag "you're sending to a token
    /// contract, not a wallet" (a classic, irreversible mistake).
    private var knownContracts: [String] { wallet.tokens.compactMap { $0.contractAddress } }

    /// Addresses the user has actually sent to before (legit recipients) — used to catch
    /// address-poisoning look-alikes. Drawn from the local activity feed.
    private var knownRecipients: [String] {
        WalletActivityStore.shared.entries
            .filter { $0.kind == .send }
            .map { $0.counterparty }
            .filter { $0.hasPrefix("0x") }
    }

    /// Full safety check on the destination. For a typed 0x address we validate it directly; for a
    /// name we validate the address it resolved to (nil while still typing/resolving a name).
    private var addressCheck: AddressValidator.Result? {
        let typed = toAddress.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return nil }
        if looksLikeName {
            guard let resolved = resolvedAddress else { return nil }   // resolve UI handles this
            return AddressValidator.validate(resolved, selfAddress: wallet.activeAddress, knownTokenContracts: knownContracts, knownRecipients: knownRecipients)
        }
        return AddressValidator.validate(typed, selfAddress: wallet.activeAddress, knownTokenContracts: knownContracts, knownRecipients: knownRecipients)
    }

    private var isValidAddress: Bool {
        guard effectiveRecipient != nil else { return false }
        return addressCheck?.isSendable ?? false
    }

    /// True when the entered amount clearly exceeds the balance. A small tolerance keeps "Max"
    /// (which uses the rounded display balance) from tripping this.
    private var amountExceedsBalance: Bool {
        guard let token = selectedToken, let amount = parsedAmount else { return false }
        let amt = (amount as NSDecimalNumber).doubleValue
        let bal = (token.balance as NSDecimalNumber).doubleValue
        return amt > bal * 1.000001 + 1e-12
    }

    private var canSend: Bool {
        guard isValidAddress, parsedAmount != nil, !amountExceedsBalance else { return false }
        // A risky destination (e.g. a token contract) requires explicit acknowledgement.
        if addressCheck?.requiresConfirm == true { return ackRisk }
        return true
    }

    /// The "Max" amount. For ETH we keep a small reserve so there's room for the gas fee (gas on
    /// Base is paid in ETH); tokens use the full balance since their gas is paid separately in ETH.
    private func maxAmount(for token: WalletToken) -> String {
        guard token.symbol == "ETH" else { return token.formattedBalance }
        let reserve = Decimal(string: "0.0001") ?? 0   // ample for a Base transfer
        let m = token.balance - reserve
        return m > 0 ? "\(m)" : "0"
    }

    // MARK: - Recipient feedback

    private var fieldBorderColor: Color {
        let typed = toAddress.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty { return .clear }
        if resolving { return Color.white.opacity(0.2) }
        guard let check = addressCheck else { return Color.white.opacity(0.2) }  // name still resolving/typing
        switch check {
        case .invalid: return WalletTheme.negative.opacity(0.6)
        case .warning: return WalletTheme.warning.opacity(0.6)
        case .ok, .info: return Color.white.opacity(0.35)
        }
    }

    @ViewBuilder
    private var addressFeedback: some View {
        if looksLikeName, let resolved = resolvedAddress {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 10)).foregroundStyle(WalletTheme.positive)
                Text("Resolves to \(abbreviated(resolved))")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(WalletTheme.textSecondary)
            }
            checkNote
        } else if looksLikeName, !resolving, !toAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            feedbackLabel("Couldn't find this name on Base.\(WalletFeatures.ens ? "" : " (Turn on ENS in Settings for .eth names.)")",
                          tone: .negative, icon: "exclamationmark.triangle.fill")
        } else {
            checkNote
        }
    }

    @ViewBuilder
    private var checkNote: some View {
        if let check = addressCheck, let msg = check.message {
            switch check {
            case .invalid:
                feedbackLabel(msg, tone: .negative, icon: "exclamationmark.triangle.fill")
            case .warning:
                VStack(alignment: .leading, spacing: 9) {
                    feedbackLabel(msg, tone: .warning, icon: "exclamationmark.triangle.fill")
                    Button { ackRisk.toggle() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: ackRisk ? "checkmark.square.fill" : "square")
                                .font(.system(size: 14)).foregroundStyle(ackRisk ? .white : WalletTheme.textTertiary)
                            Text("I understand — send anyway")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(11)
                .background(WalletTheme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(WalletTheme.warning.opacity(0.3), lineWidth: 0.8))
            case .info:
                feedbackLabel(msg, tone: .neutral, icon: "info.circle")
            case .ok:
                EmptyView()
            }
        }
    }

    private enum FeedbackTone {
        case negative, warning, neutral
        var color: Color {
            switch self {
            case .negative: return WalletTheme.negative
            case .warning:  return WalletTheme.warning
            case .neutral:  return WalletTheme.textSecondary
            }
        }
    }

    private func feedbackLabel(_ text: String, tone: FeedbackTone, icon: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10)).foregroundStyle(tone.color).padding(.top, 1)
            }
            Text(text).font(.system(size: 11)).foregroundStyle(tone.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {

                // Success banner (shown after a broadcast)
                if let txHash = sentTxHash {
                    Button {
                        if let url = URL(string: wallet.explorerTxURL(txHash)) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.white)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Transaction broadcast")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("\(abbreviated(txHash)) · View on \(wallet.activeChain.explorerName)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.5))
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(white: 0.4))
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Token selector
                fieldLabel("Coin")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(wallet.visibleTokens) { token in
                            Button {
                                selectedTokenID = token.id
                            } label: {
                                HStack(spacing: 7) {
                                    TokenIconView(token: token, size: 20)
                                    Text(token.symbol)
                                        .font(.system(size: 12, weight: selectedTokenID == token.id ? .semibold : .regular))
                                        .foregroundStyle(selectedTokenID == token.id ? .white : Color(white: 0.45))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    selectedTokenID == token.id
                                    ? WalletTheme.surfaceSelected
                                    : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                }
                .background(WalletTheme.surfaceField, in: RoundedRectangle(cornerRadius: 10))

                // Contract address for selected token (copy it)
                if let token = selectedToken, let addr = token.contractAddress {
                    HStack(spacing: 8) {
                        Text("Contract:")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(white: 0.35))
                        Text(abbreviated(addr))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(white: 0.35))
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(addr, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(white: 0.3))
                        }
                        .buttonStyle(.plain)
                        .help("Copy contract address")
                    }
                }

                // Recipient
                HStack {
                    fieldLabel("Send to")
                    Spacer()
                    if !contacts.contacts.isEmpty {
                        Button { showContacts = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "person.crop.circle").font(.system(size: 11))
                                Text("Contacts").font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("0x… or name.base.eth", text: $toAddress)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white)
                        .onChange(of: toAddress) { _, _ in ackRisk = false; resolveNameIfNeeded() }
                    if resolving { ProgressView().controlSize(.mini).scaleEffect(0.7) }
                    if !toAddress.isEmpty {
                        Button { toAddress = ""; resolvedAddress = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color(white: 0.3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(WalletTheme.surfaceField, in: RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(fieldBorderColor, lineWidth: 1)
                )

                addressFeedback

                // Saved-contact name, or an offer to save a new valid address.
                if isValidAddress, let recipient = effectiveRecipient {
                    if let name = contacts.label(for: recipient) {
                        HStack(spacing: 5) {
                            Image(systemName: "person.crop.circle.fill").font(.system(size: 10)).foregroundStyle(WalletTheme.textSecondary)
                            Text("Saved as \(name)").font(.system(size: 11)).foregroundStyle(WalletTheme.textSecondary)
                        }
                    } else {
                        Button { contactLabel = ""; savingContact = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "person.badge.plus").font(.system(size: 10))
                                Text("Save to contacts").font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(WalletTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Amount
                HStack {
                    fieldLabel("Amount")
                    Spacer()
                    if let token = selectedToken, token.balance > 0 {
                        Button("Max") { amountText = maxAmount(for: token) }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("0.00", text: $amountText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(selectedToken?.symbol ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.4))
                }
                .padding(12)
                .background(WalletTheme.surfaceField, in: RoundedRectangle(cornerRadius: 9))

                if amountExceedsBalance {
                    feedbackLabel("That's more than your \(selectedToken?.symbol ?? "") balance.",
                                  tone: .negative, icon: "exclamationmark.triangle.fill")
                } else if let token = selectedToken, let amount = parsedAmount {
                    let usd = (amount as NSDecimalNumber).doubleValue * token.priceUSD
                    if usd > 0 {
                        Text("≈ \(wallet.formatFiat(usd))")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(white: 0.4))
                    }
                }

                // Gas speed selector
                fieldLabel("Network Fee")
                HStack(spacing: 6) {
                    ForEach(GasSpeed.allCases) { speed in
                        Button { gasSpeed = speed } label: {
                            HStack(spacing: 5) {
                                Image(systemName: speed.symbol).font(.system(size: 10))
                                Text(speed.label).font(.system(size: 11, weight: gasSpeed == speed ? .semibold : .regular))
                            }
                            .foregroundStyle(gasSpeed == speed ? .black : Color(white: 0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(gasSpeed == speed ? Color.white : WalletTheme.surfaceField,
                                        in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "fuelpump")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.3))
                    Text("Gas paid in \(wallet.activeChain.nativeSymbol) on \(wallet.activeChain.name) · estimated at runtime")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.3))
                }

                if !sendError.isEmpty {
                    Text(sendError)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
                }

                // Send button
                Button { showConfirm = true } label: {
                    HStack {
                        Spacer()
                        if isSending {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Send \(selectedToken?.symbol ?? "")")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(WalletTheme.primaryFill(enabled: canSend))
                    .foregroundStyle(WalletTheme.primaryText(enabled: canSend))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .disabled(!canSend || isSending)
            }
            .padding(20)
        }
        .sheet(isPresented: $showConfirm) { sendConfirmSheet }
        .sheet(isPresented: $showContacts) { contactsPicker }
        .alert("Save contact", isPresented: $savingContact) {
            TextField("Name", text: $contactLabel)
            Button("Save") {
                if let r = effectiveRecipient { contacts.add(address: r, label: contactLabel) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(effectiveRecipient.map { abbreviated($0) } ?? "")
        }
    }

    // MARK: - Contacts picker

    private var contactsPicker: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Contacts").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Button { showContacts = false } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WalletTheme.textSecondary).frame(width: 28, height: 28)
                        .background(WalletTheme.surfaceStrong, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider().opacity(0.1)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(contacts.contacts) { c in
                        Button {
                            toAddress = c.address; showContacts = false
                        } label: {
                            HStack(spacing: 12) {
                                AccountAvatar(address: c.address, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                    Text(c.shortAddress).font(.system(size: 11, design: .monospaced)).foregroundStyle(WalletTheme.textTertiary)
                                }
                                Spacer()
                            }
                            .padding(12).walletCard(radius: 12)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { contacts.remove(id: c.id) } label: {
                                Label("Delete contact", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 360).frame(minHeight: 300, maxHeight: 500)
        .background(WalletTheme.canvas)
        .preferredColorScheme(.dark)
    }

    // MARK: - Confirm sheet

    private var sendConfirmSheet: some View {
        VStack(spacing: 20) {
            Text("Confirm Transaction")
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 24)

            VStack(spacing: 0) {
                confirmRow("Token",   value: selectedToken?.symbol ?? "")
                Divider().opacity(0.08)
                confirmRow("Amount",  value: "\(amountText) \(selectedToken?.symbol ?? "")")
                Divider().opacity(0.08)
                confirmRow("To",      value: abbreviated(effectiveRecipient ?? toAddress), mono: true)
                Divider().opacity(0.08)
                confirmRow("Network", value: wallet.activeChain.name)
            }
            .background(WalletTheme.surfaceField, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24)

            VStack(spacing: 10) {
                if wallet.biometricUnlockEnabled && wallet.biometricAvailable {
                    Button {
                        Task { await submitSendWithBiometrics() }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: WalletBiometric.symbol)
                                .font(.system(size: 14))
                            Text("Authorize with \(WalletBiometric.label)")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: 220)
                        .padding(.vertical, 11)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Text("or enter your PIN")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.4))
                } else {
                    Text("Enter your PIN to authorize")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.4))
                }

                HStack(spacing: 12) {
                    ForEach(0..<WalletConfig.pinLength, id: \.self) { i in
                        Circle()
                            .fill(i < pin.count ? Color.white : Color(white: 0.2))
                            .frame(width: 11, height: 11)
                    }
                }

                if pinError {
                    Text("Incorrect PIN")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
                }

                PINKeypad(pin: $pin, maxLength: WalletConfig.pinLength) { submitSend() }
                    .frame(maxWidth: 220)
            }

            Button("Cancel") { showConfirm = false; pin = ""; pinError = false }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding(.bottom, 24)
        }
        .frame(width: 360)
        .background(WalletTheme.canvas)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(white: 0.4))
    }

    @ViewBuilder
    private func confirmRow(_ label: String, value: String, mono: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.4))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: mono ? .monospaced : .default))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func abbreviated(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }

    private func submitSend() {
        guard wallet.attemptPIN(pin) else { pinError = true; pin = ""; return }
        broadcast(pinForSigning: pin)
        pin = ""
    }

    private func submitSendWithBiometrics() async {
        guard let pinForSigning = await wallet.authorizeSigningWithBiometrics(
            reason: "Authorize this transaction") else { return }
        broadcast(pinForSigning: pinForSigning)
    }

    private func resolveNameIfNeeded() {
        resolveTask?.cancel()
        resolvedAddress = nil
        let name = toAddress.trimmingCharacters(in: .whitespaces).lowercased()

        // PRIVACY: only look up a *complete-looking* name, and only after the user pauses typing.
        // Otherwise every keystroke ("v", "vi", "vita…") would be sent to the RPC, leaking what
        // you're typing and who you're about to pay.
        let complete = name.hasSuffix(".eth") || name.hasSuffix(".base")
        guard looksLikeName, complete else { resolving = false; return }

        resolving = true
        resolveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)   // debounce
            if Task.isCancelled { return }
            let resolved = await WalletNetwork.resolveName(name)
            if Task.isCancelled { return }
            if toAddress.trimmingCharacters(in: .whitespaces).lowercased() == name {
                resolvedAddress = resolved
                resolving = false
            }
        }
    }

    private func broadcast(pinForSigning: String) {
        showConfirm = false
        pinError = false
        isSending = true
        guard let token = selectedToken, let amount = parsedAmount, let recipient = effectiveRecipient else {
            isSending = false; return
        }
        Task {
            let success = await wallet.send(to: recipient, amount: amount, token: token,
                                            pin: pinForSigning, speed: gasSpeed)
            isSending = false
            if success {
                sentTxHash = wallet.lastTxHash
                toAddress = ""
                amountText = ""
                sendError = ""
            } else {
                sendError = wallet.lastError ?? "Transaction failed."
            }
        }
    }
}
