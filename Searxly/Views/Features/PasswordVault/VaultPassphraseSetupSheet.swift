//
//  VaultPassphraseSetupSheet.swift
//  Searxly
//

import SwiftUI

struct VaultPassphraseSetupSheet: View {
    enum Mode {
        case enable
        case change
        case disable

        var title: String {
            switch self {
            case .enable: return "Set Vault Passphrase"
            case .change: return "Change Vault Passphrase"
            case .disable: return "Remove Vault Passphrase"
            }
        }

        var confirmLabel: String {
            switch self {
            case .enable: return "Enable Passphrase"
            case .change: return "Save New Passphrase"
            case .disable: return "Remove Passphrase"
            }
        }
    }

    let mode: Mode
    let onCancel: () -> Void
    let onComplete: () -> Void

    @State private var currentPassphrase = ""
    @State private var newPassphrase = ""
    @State private var confirmPassphrase = ""
    @State private var errorMessage: String?

    private let lockManager = VaultLockManager.shared
    private let minimumLength = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(mode.title)
                .font(.title2.weight(.semibold))

            Text(modeDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                if mode == .change || mode == .disable {
                    secureField("Current passphrase", text: $currentPassphrase)
                }

                if mode != .disable {
                    secureField(mode == .change ? "New passphrase" : "Vault passphrase", text: $newPassphrase)
                    secureField("Confirm passphrase", text: $confirmPassphrase)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .buttonStyle(.bordered)

                Spacer()

                Button(mode.confirmLabel) {
                    submit()
                }
                .buttonStyle(.bordered)
                .disabled(!canSubmit)
            }
        }
        .padding(28)
        .frame(width: 420)
    }

    private var modeDescription: String {
        switch mode {
        case .enable:
            return "Require this passphrase to unlock the vault instead of Touch ID. Passwords remain in the Keychain with device protection."
        case .change:
            return "Enter your current passphrase and choose a new one."
        case .disable:
            return "Confirm your current passphrase to return to Touch ID / Mac password unlock."
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .enable:
            return newPassphrase.count >= minimumLength && newPassphrase == confirmPassphrase
        case .change:
            return !currentPassphrase.isEmpty
                && newPassphrase.count >= minimumLength
                && newPassphrase == confirmPassphrase
        case .disable:
            return !currentPassphrase.isEmpty
        }
    }

    @ViewBuilder
    private func secureField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            SecureField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func submit() {
        errorMessage = nil

        switch mode {
        case .enable:
            guard newPassphrase == confirmPassphrase else {
                errorMessage = "Passphrases do not match."
                return
            }
            guard lockManager.setCustomPassphrase(newPassphrase) else {
                errorMessage = "Passphrase must be at least \(minimumLength) characters."
                return
            }
            onComplete()

        case .change:
            guard lockManager.changePassphrase(from: currentPassphrase, to: newPassphrase) else {
                errorMessage = "Current passphrase is incorrect or the new one is too short."
                return
            }
            onComplete()

        case .disable:
            guard lockManager.removeCustomPassphrase(verifying: currentPassphrase) else {
                errorMessage = "Current passphrase is incorrect."
                return
            }
            onComplete()
        }
    }
}