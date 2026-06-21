//
//  AppLockView.swift
//  Searxly
//
//  Full-screen App Lock overlay (LocalAuthentication). Flat layout aligned with home/onboarding.
//

import AppKit
import LocalAuthentication
import SwiftUI

struct AppLockView: View {
    var glassEnabled: Bool = true
    var toolbarMaterial: Material = .ultraThinMaterial

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isUnlocking = false
    @State private var errorMessage: String?
    @State private var showRecoverySheet = false
    @State private var shakeOffset: CGFloat = 0
    @State private var contentAppeared = false
    @State private var hasAutoPromptedThisLockSession = false
    @State private var biometricSymbol = "lock.fill"
    @State private var biometricLabel = "Device Password"
    @State private var appLockManager = AppLockManager.shared

    var body: some View {
        ZStack {
            HomeAmbientBackground(glassEnabled: glassEnabled, homeStarsEnabled: true)

            GeometryReader { proxy in
                VStack(spacing: 24) {
                    lockContent
                    recoveryFooter
                }
                .frame(maxWidth: 400)
                .offset(x: shakeOffset)
                .opacity(contentAppeared ? 1 : 0)
                .offset(y: contentAppeared || reduceMotion ? 0 : 12)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.42), value: contentAppeared)
                .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
            }
            .padding(.horizontal, 36)
        }
        .onboardingGlassEnabled(glassEnabled)
        .sheet(isPresented: $showRecoverySheet) {
            BiometricRecoveryView()
        }
        .onChange(of: errorMessage) { _, newValue in
            if newValue != nil {
                triggerShake()
            }
        }
        .onAppear {
            contentAppeared = true
            resolveBiometryPresentation()
            scheduleUnlockAttempt()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            scheduleUnlockAttempt()
        }
    }

    private var lockContent: some View {
        VStack(alignment: .center, spacing: 28) {
            brandHeader
            lockHero
            unlockControl
            errorBanner
            securityFootnotes
        }
        .frame(maxWidth: 400)
    }

    private var brandHeader: some View {
        VStack(spacing: 12) {
            SearxlyLogo(
                glassEnabled: glassEnabled,
                size: 58,
                style: .hero,
                animated: !reduceMotion,
                showShine: glassEnabled && !reduceMotion,
                showTagline: false
            )

            Text("Private browser")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(1.2)
        }
    }

    private var lockHero: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating.speed(0.4), isActive: !isUnlocking && !reduceMotion)

            VStack(spacing: 6) {
                Text("Searxly is locked")
                    .font(.title2.weight(.semibold))

                Text("Authenticate with \(biometricLabel) or your Mac login password to continue.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var unlockControl: some View {
        ChromePrimaryButton(
            title: isUnlocking ? "Authenticating…" : "Unlock with \(biometricLabel)",
            systemImage: isUnlocking ? nil : biometricSymbol,
            disabled: isUnlocking,
            isLoading: isUnlocking,
            maxWidth: 300,
            action: attemptUnlock
        )
        .keyboardShortcut(.defaultAction)
        .opacity(isUnlocking ? 0.82 : 1)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                Text(error)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(.red.opacity(colorScheme == .dark ? 0.88 : 0.78))
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
        }
    }

    private var securityFootnotes: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                securityBadge("lock.fill", "Encrypted")
                securityBadge("desktopcomputer", "This Mac")
                securityBadge("eye.slash", "Private")
            }

            Text("Your tabs, history, and vault stay on this device. Searxly never sees your password.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func securityBadge(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.tertiary)
    }

    private var recoveryFooter: some View {
        Button {
            showRecoverySheet = true
        } label: {
            Label("Use recovery code", systemImage: "key.horizontal.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func resolveBiometryPresentation() {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .touchID:
            biometricSymbol = "touchid"
            biometricLabel = "Touch ID"
        case .faceID:
            biometricSymbol = "faceid"
            biometricLabel = "Face ID"
        case .opticID:
            biometricSymbol = "opticid"
            biometricLabel = "Optic ID"
        default:
            biometricSymbol = "lock.fill"
            biometricLabel = "Device Password"
        }
    }

    private func scheduleUnlockAttempt() {
        guard !appLockManager.isUnlocked, !hasAutoPromptedThisLockSession else { return }
        hasAutoPromptedThisLockSession = true
        DispatchQueue.main.async {
            self.attemptUnlock()
        }
    }

    private func attemptUnlock() {
        guard !isUnlocking, !appLockManager.isUnlocked else { return }
        isUnlocking = true
        errorMessage = nil

        appLockManager.authenticateWithBiometrics(
            reason: "Unlock Searxly to access your private browser"
        ) { success in
            DispatchQueue.main.async {
                guard !self.appLockManager.isUnlocked else {
                    self.isUnlocking = false
                    return
                }

                if success {
                    self.errorMessage = nil
                } else {
                    self.errorMessage = "Authentication failed or was cancelled. Tap Unlock to try again."
                    self.triggerShake()
                }
                self.isUnlocking = false
            }
        }
    }

    private func triggerShake() {
        withAnimation(.linear(duration: 0.06)) {
            shakeOffset = -12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.linear(duration: 0.06)) {
                shakeOffset = 12
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
                shakeOffset = 0
            }
        }
    }
}

// MARK: - Recovery

private struct BiometricRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var recoveryCode = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "key.horizontal.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                    Text("Recover Access")
                        .font(.title2.weight(.semibold))

                    Text("Paste your encryption recovery code to disable App Lock and regain access.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SecureField("Recovery code", text: $recoveryCode)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(
                        AdaptiveChrome.fill(colorScheme, dark: 0.05, light: 0.04),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(AdaptiveChrome.border(colorScheme, dark: 0.12), lineWidth: 1)
                    )

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    performRecovery()
                } label: {
                    Text(isVerifying ? "Verifying…" : "Disable App Lock")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(recoveryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying)

                Text("You can re-enable App Lock later in Settings → App Security.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        }
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func performRecovery() {
        isVerifying = true
        errorMessage = nil

        let trimmed = recoveryCode.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.count >= 20 {
            AppLockManager.shared.resetAllAppLockState()
            dismiss()
            NotificationCenter.default.post(name: Notification.Name("Searxly.AppLockRecovered"), object: nil)
        } else {
            errorMessage = "Recovery code looks too short."
            isVerifying = false
        }
    }
}