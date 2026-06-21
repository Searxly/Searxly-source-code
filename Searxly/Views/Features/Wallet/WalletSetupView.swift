//
//  WalletSetupView.swift
//  Searxly
//
//  Multi-step flow: Choose → Create/Import → PIN → Recovery code → Done.
//

import SwiftUI

struct WalletSetupView: View {
    /// Provided when hosted in the wallet overlay (which has no sheet `dismiss`); falls back to the
    /// environment dismiss when used standalone.
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("reduceLiquidGlass") private var reduceLiquidGlass = false
    private var glassEnabled: Bool { !reduceLiquidGlass }

    enum SetupStep {
        case choose
        case seedDisplay([String])          // creating: show generated words
        case seedImport                     // importing: user enters words
        case seedConfirmWarning([String])   // after display: "did you write it down?"
        case pinSetup([String])             // set 6-digit PIN
        case recoveryCode(String, [String]) // show one-time recovery code
        case done
    }

    @State private var step: SetupStep = .choose
    @State private var wallet = WalletManager.shared
    @State private var importText = ""
    @State private var importError = ""
    @State private var seedRevealed = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.12)

            Group {
                switch step {
                case .choose:             chooseView
                case .seedDisplay(let w): seedDisplayView(words: w)
                case .seedImport:         seedImportView
                case .seedConfirmWarning(let w): warningView(words: w)
                case .pinSetup(let w):    PINSetupStepView(words: w, wallet: wallet, onDone: { pin, mnemonic in
                    let code = wallet.prepareNewWallet(mnemonic: mnemonic, pin: pin)
                    step = .recoveryCode(code, mnemonic)
                })
                case .recoveryCode(let code, _): recoveryCodeView(code: code)
                case .done: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            SearxlyWalletBadge(size: 32, cornerRadius: 8, glassEnabled: glassEnabled)
            Text("Set Up Wallet")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Button { if let onClose { onClose() } else { dismiss() } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .glassIcon(size: 30, glassEnabled: glassEnabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Choose

    private var chooseView: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 10) {
                Text("A crypto wallet,\nbuilt into your browser")
                    .font(.system(size: 23, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Hold and send coins on Base. Only you can\naccess it — your keys never leave this Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                setupOptionCard(
                    icon: "sparkles",
                    title: "Create a new wallet",
                    subtitle: "We'll give you a 12-word backup phrase to write down."
                ) {
                    let words = wallet.generateMnemonic()
                    step = .seedDisplay(words)
                }

                setupOptionCard(
                    icon: "square.and.arrow.down",
                    title: "I already have a wallet",
                    subtitle: "Restore it with your 12 or 24-word recovery phrase."
                ) {
                    step = .seedImport
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    @ViewBuilder
    private func setupOptionCard(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(white: 0.10), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Seed display

    private func seedDisplayView(words: [String]) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Your 12-word backup phrase")
                    .font(.system(size: 18, weight: .semibold))
                Text("These 12 words are the master key to your wallet. Write them down in order, on paper, and keep them somewhere safe. This is the only way to get back in if you lose this Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            // Critical warning
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 13)).foregroundStyle(.orange).padding(.top, 1)
                Text("Anyone with these words can take your funds. Never type them into a website and never share them — Searxly will never ask for them.")
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.22), lineWidth: 0.8))
            .padding(.horizontal, 24)

            // 12-word grid (3 columns × 4 rows), blurred until revealed
            ZStack {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        HStack(spacing: 6) {
                            Text("\(index + 1).")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 22, alignment: .trailing)
                            Text(word)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 24)
                .blur(radius: seedRevealed ? 0 : 9)

                if !seedRevealed {
                    Button { withAnimation { seedRevealed = true } } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "eye.fill").font(.system(size: 18))
                            Text("Tap to reveal").font(.system(size: 12, weight: .semibold))
                            Text("Make sure no one is watching").font(.system(size: 10)).foregroundStyle(Color(white: 0.5))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Button("Back") { seedRevealed = false; step = .choose }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                Spacer()

                Button("I Wrote It Down") {
                    seedRevealed = false
                    step = .seedConfirmWarning(words)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .controlSize(.regular)
                .disabled(!seedRevealed)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Import seed

    private var seedImportView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Import Wallet")
                    .font(.system(size: 18, weight: .semibold))
                Text("Enter your 12 or 24-word seed phrase, separated by spaces.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            TextEditor(text: $importText)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 10))
                .frame(height: 120)
                .padding(.horizontal, 24)
                .onChange(of: importText) { _, _ in importError = "" }

            if !importError.isEmpty {
                Text(importError)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 1, green: 0.33, blue: 0.33))
            }

            HStack(spacing: 10) {
                Button("Back") { step = .choose }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                Spacer()

                Button("Next") { validateAndImport() }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .controlSize(.regular)
                    .disabled(importText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func validateAndImport() {
        let words = importText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        switch BIP39.validate(words) {
        case .ok:
            step = .pinSetup(words)
        case .badLength:
            importError = "Please enter exactly 12 or 24 words."
        case .unknownWord(let w):
            importError = "“\(w)” isn’t a valid recovery word. Check your spelling."
        case .badChecksum:
            importError = "That phrase has a typo or the words are out of order — its checksum doesn’t match. Re-check each word."
        }
    }

    // MARK: - Warning

    private func warningView(words: [String]) -> some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
            }
            VStack(spacing: 8) {
                Text("Have you saved your seed phrase?")
                    .font(.system(size: 18, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text("If you lose your seed phrase, you will permanently lose access to this wallet. Searxly cannot recover it.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                Button("Yes, I Saved It — Continue") { step = .pinSetup(words) }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .controlSize(.large)

                Button("Go Back") { step = .seedDisplay(words) }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Recovery code display

    private func recoveryCodeView(code: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 72, height: 72)
                Image(systemName: "key.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("Your PIN reset code")
                    .font(.system(size: 18, weight: .semibold))
                Text("If you forget your PIN, this code lets you set a new one. It's different from your 12-word phrase. Save it somewhere safe — you'll only see it once.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Recovery code display
            HStack {
                Text(formattedRecoveryCode(code))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(14)
                    .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 10))

                Button {
                    // Sensitive: concealed copy that auto-clears (won't sync via Universal Clipboard).
                    VaultClipboardManager.shared.copySensitive(code)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy recovery code (auto-clears in 45s)")
            }
            .padding(.horizontal, 24)

            Button("Done — Open Wallet") {
                wallet.activateUnlock()
                // WalletPanelView will switch to unlocked content once unlockState changes.
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .controlSize(.large)

            Spacer()
        }
    }

    private func formattedRecoveryCode(_ code: String) -> String {
        // Format as XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX
        var result = ""
        for (i, char) in code.enumerated() {
            if i > 0 && i % 4 == 0 { result.append("-") }
            result.append(char)
        }
        return result
    }
}

// MARK: - PIN setup step (extracted for compiler tractability)

private struct PINSetupStepView: View {
    let words: [String]
    let wallet: WalletManager
    let onDone: (String, [String]) -> Void

    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var isConfirming = false
    @State private var mismatch = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 6) {
                Text(isConfirming ? "Confirm PIN" : "Set a 6-Digit PIN")
                    .font(.system(size: 18, weight: .semibold))
                Text(isConfirming
                     ? "Enter the same PIN again to confirm."
                     : "You'll use this PIN every time you open your wallet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 14) {
                let displayPin = isConfirming ? confirmPin : pin
                ForEach(0..<WalletConfig.pinLength, id: \.self) { i in
                    Circle()
                        .fill(i < displayPin.count ? Color.white : Color(white: 0.20))
                        .frame(width: 14, height: 14)
                        .animation(.spring(response: 0.2), value: displayPin.count)
                }
            }

            if mismatch {
                Text("PINs don't match. Try again.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 1, green: 0.33, blue: 0.33))
                    .transition(.opacity)
            }

            PINKeypad(pin: isConfirming ? $confirmPin : $pin, maxLength: WalletConfig.pinLength) {
                handleComplete()
            }
            .frame(maxWidth: 240)

            Spacer()
        }
    }

    private func handleComplete() {
        if !isConfirming {
            isConfirming = true
        } else {
            if pin == confirmPin {
                onDone(pin, words)
            } else {
                mismatch = true
                confirmPin = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    mismatch = false
                    isConfirming = false
                    pin = ""
                }
            }
        }
    }
}
