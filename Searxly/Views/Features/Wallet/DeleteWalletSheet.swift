//
//  DeleteWalletSheet.swift
//  Searxly
//
//  A deliberate, hard-to-do-by-accident wallet deletion flow. Explains exactly what happens,
//  requires confirming the recovery phrase is backed up, enforces a short cooldown before the
//  destructive button activates, and (when a PIN is known) requires the PIN.
//

import SwiftUI
import Combine

struct DeleteWalletSheet: View {
    /// When true, the user is locked out (no PIN) — this is the "I lost everything, wipe it" path,
    /// so we don't ask for a PIN but we keep all the other safeguards.
    var requiresPIN: Bool = true
    var onCancel: () -> Void
    var onConfirmed: () -> Void

    @State private var wallet = WalletManager.shared
    @State private var backedUp = false
    @State private var pin = ""
    @State private var pinError = false
    @State private var secondsLeft = 5
    @State private var ticking = true

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var canDelete: Bool {
        backedUp && secondsLeft == 0 && (!requiresPIN || pin.count == WalletConfig.pinLength)
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Color(red: 1, green: 0.35, blue: 0.35).opacity(0.12)).frame(width: 64, height: 64)
                Image(systemName: "trash.fill").font(.system(size: 26)).foregroundStyle(Color(red: 1, green: 0.42, blue: 0.42))
            }
            .padding(.top, 24)

            Text("Delete this wallet?")
                .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)

            // What happens
            VStack(alignment: .leading, spacing: 10) {
                consequence("This removes the wallet and its keys from this device.")
                consequence("Your funds are NOT moved — they stay on the blockchain at your address.")
                consequence("The ONLY way back in is your 12-word recovery phrase. Without it, access is gone forever.")
            }
            .padding(14)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)

            // Backup confirmation
            Button { backedUp.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: backedUp ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16)).foregroundStyle(backedUp ? .white : Color(white: 0.4))
                    Text("I've written down my 12-word recovery phrase")
                        .font(.system(size: 12)).foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)

            // PIN (when known)
            if requiresPIN {
                VStack(spacing: 8) {
                    Text("Enter your PIN to confirm").font(.system(size: 11)).foregroundStyle(Color(white: 0.45))
                    SecureField("PIN", text: $pin)
                        .textFieldStyle(.plain).multilineTextAlignment(.center)
                        .font(.system(size: 14, design: .monospaced))
                        .frame(width: 120).padding(.vertical, 8)
                        .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 8))
                    if pinError {
                        Text("Incorrect PIN").font(.system(size: 11)).foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
                    }
                }
            }

            // Actions
            HStack(spacing: 10) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)

                Button {
                    if requiresPIN && !wallet.attemptPIN(pin) { pinError = true; return }
                    onConfirmed()
                } label: {
                    Text(secondsLeft > 0 ? "Delete (\(secondsLeft))" : "Delete Wallet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canDelete ? .white : Color(white: 0.4))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(canDelete ? Color(red: 0.85, green: 0.25, blue: 0.25) : Color(white: 0.12),
                                    in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain).disabled(!canDelete)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 380)
        .background(WalletTheme.canvas)
        .preferredColorScheme(.dark)
        .onReceive(ticker) { _ in if secondsLeft > 0 { secondsLeft -= 1 } }
    }

    private func consequence(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(Color(white: 0.5)).padding(.top, 1)
            Text(text).font(.system(size: 12)).foregroundStyle(Color(white: 0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
