//
//  OnboardingWelcomeStep.swift
//  Searxly
//

import SwiftUI

struct OnboardingWelcomeStep: View {
    let glassEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            // Logo — floats against the starfield like the home page
            SearxlyLogo(
                glassEnabled: glassEnabled,
                size: 66,
                style: .hero,
                animated: !reduceMotion,
                showShine: glassEnabled && !reduceMotion,
                showTagline: false
            )
            .onboardingVisualReveal(revealed, reduceMotion: reduceMotion, delay: 0)
            .padding(.bottom, 28)

            // Headline
            VStack(spacing: 8) {
                Text("Your search stays on your Mac.")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text("A native browser with its own private SearXNG engine.\nNo accounts, no cloud, nothing that can be leaked.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .onboardingVisualReveal(revealed, reduceMotion: reduceMotion, delay: 0.07)
            .padding(.bottom, 32)

            // Feature rows
            VStack(spacing: 8) {
                featureRow(
                    icon: "magnifyingglass",
                    title: "Local search engine",
                    detail: "SearXNG runs entirely on this Mac — your queries never touch any server."
                )
                featureRow(
                    icon: "lock.fill",
                    title: "On-device vault",
                    detail: "Passwords and history encrypted with keys that never leave Keychain."
                )
                featureRow(
                    icon: "person.crop.circle.badge.xmark",
                    title: "No accounts",
                    detail: "Nothing to sign in to, nothing to sync, nothing to breach."
                )
            }
            .onboardingVisualReveal(revealed, reduceMotion: reduceMotion, delay: 0.14)
        }
        .frame(maxWidth: 500, alignment: .center)
        .frame(maxWidth: .infinity)
        .onAppear { revealed = true }
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Icon badge
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AdaptiveChrome.fill(colorScheme, dark: glassEnabled ? 0.10 : 0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            AdaptiveChrome.border(colorScheme, dark: 0.20),
                                            AdaptiveChrome.border(colorScheme, dark: 0.06)
                                        ],
                                        startPoint: .top, endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 6, y: 3)
                .padding(.top, 1)

            // Text
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.92))
                Text(detail)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AdaptiveChrome.fill(colorScheme, dark: glassEnabled ? 0.07 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AdaptiveChrome.border(colorScheme, dark: 0.10), lineWidth: 1)
                )
        )
    }
}
