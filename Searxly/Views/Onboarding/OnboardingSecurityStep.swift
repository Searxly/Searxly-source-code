//
//  OnboardingSecurityStep.swift
//  Searxly
//

import AppKit
import SwiftUI

struct OnboardingSecurityStep: View {
    @Binding var selectedEncryptionChoice: Bool?
    @Binding var usedMaximumPrivacyPreset: Bool
    @Binding var usedSecureMacPreset: Bool
    @Binding var recoveryCodeInOnboarding: String?
    @Binding var encryptionSetupError: String?
    @Binding var showRecoveryCopied: Bool
    @Binding var showRecoveryDownloaded: Bool
    @Binding var recoveryDownloadError: String?
    @Binding var isSavingRecoveryFile: Bool

    @Binding var appLockEnabledInThisSession: Bool
    @Binding var isPerformingAppLockAuth: Bool
    @Binding var appLockSetupError: String?

    let onMaximumPrivacy: () -> Void
    let onSecureMac: () -> Void
    let onUseDefaults: () -> Void
    let onEnableAppLock: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            OnboardingStepHero(
                icon: "shield.lefthalf.filled",
                title: "Choose your privacy level",
                subtitle: "Searxly is private out of the box. Pick how locked-down you want it — you can change any of this later in Settings."
            )

            VStack(spacing: 10) {
                OnboardingChoiceRow(
                    title: "Maximum Privacy",
                    subtitle: "Every tab private, no history, cookies and cache cleared, Local AI off.",
                    icon: "eye.slash.fill",
                    badge: "Recommended",
                    isSelected: usedMaximumPrivacyPreset
                ) {
                    onMaximumPrivacy()
                }

                OnboardingChoiceRow(
                    title: "Secure this Mac",
                    subtitle: "Encrypt local data, generate a recovery code, and keep no history.",
                    icon: "lock.laptopcomputer",
                    badge: "Advanced",
                    isSelected: usedSecureMacPreset && selectedEncryptionChoice == true
                ) {
                    onSecureMac()
                }

                OnboardingChoiceRow(
                    title: "Keep defaults",
                    subtitle: "Stay with the privacy-first setup already applied — encrypted, no history.",
                    icon: "checkmark.shield.fill",
                    isSelected: selectedEncryptionChoice == false && !usedMaximumPrivacyPreset && !usedSecureMacPreset
                ) {
                    onUseDefaults()
                }
            }

            if let error = encryptionSetupError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let code = recoveryCodeInOnboarding {
                encryptionRecoveryCard(code: code)
            }

            OnboardingFlatDivider()

            VStack(spacing: 10) {
                OnboardingChoiceRow(
                    title: "Enable App Lock",
                    subtitle: "Require Touch ID or your Mac password every time Searxly opens.",
                    icon: "faceid",
                    badge: "Optional",
                    isSelected: appLockEnabledInThisSession,
                    trailing: AnyView(
                        Group {
                            if isPerformingAppLockAuth {
                                ProgressView().scaleEffect(0.8)
                            } else if appLockEnabledInThisSession {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    )
                ) {
                    onEnableAppLock()
                }
                .disabled(appLockEnabledInThisSession || isPerformingAppLockAuth)

                if let appLockSetupError {
                    Text(appLockSetupError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .animation(OnboardingStyle.stepSpring, value: selectedEncryptionChoice)
    }

    private func encryptionRecoveryCard(code: String) -> some View {
        OnboardingInsetCard {
            VStack(alignment: .center, spacing: 12) {
                Text("Your recovery code")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)

                Text("Save this somewhere safe. You'll need it if your Keychain is reset or you move to a new Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(String(repeating: "•", count: 28))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text("Hidden on screen for security. Copy or download to save it.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                HStack(spacing: 10) {
                    OnboardingActionCard(title: "Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                        showRecoveryCopied = true
                        showRecoveryDownloaded = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(2200))
                            showRecoveryCopied = false
                        }
                    }
                    .frame(maxWidth: .infinity)

                    OnboardingActionCard(
                        title: isSavingRecoveryFile ? "Saving…" : "Download",
                        systemImage: "arrow.down.doc",
                        disabled: isSavingRecoveryFile
                    ) {
                        Task { @MainActor in
                            isSavingRecoveryFile = true
                            recoveryDownloadError = nil
                            if await PrivacyManager.shared.saveRecoveryCodeToFile(code) != nil {
                                showRecoveryDownloaded = true
                                showRecoveryCopied = false
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(2600))
                                    showRecoveryDownloaded = false
                                }
                            } else {
                                recoveryDownloadError = "Save cancelled or the file could not be written."
                            }
                            isSavingRecoveryFile = false
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if let recoveryDownloadError {
                    Text(recoveryDownloadError)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if showRecoveryCopied {
                    Text("Copied to clipboard.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if showRecoveryDownloaded {
                    Text("Recovery file saved.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}