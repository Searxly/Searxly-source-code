//
//  OnboardingReadyStep.swift
//  Searxly
//

import SwiftUI

struct OnboardingReadyStep: View {
    let glassEnabled: Bool
    let localSearchReady: Bool
    let privacyLabel: String
    let appLockEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 0) {
            // Logo
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
                Text("You're all set.")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text("Everything runs right here on your Mac.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .onboardingVisualReveal(revealed, reduceMotion: reduceMotion, delay: 0.06)
            .padding(.bottom, 28)

            // Summary rows
            VStack(spacing: 8) {
                summaryRow(
                    icon: localSearchReady ? "checkmark.circle.fill" : "circle.dotted",
                    title: localSearchReady ? "Local SearXNG active" : "Local search",
                    detail: localSearchReady
                        ? "Private SearXNG is running on this Mac."
                        : "Not set up yet — start it anytime in Settings.",
                    accent: localSearchReady
                )

                summaryRow(
                    icon: "shield.fill",
                    title: privacyLabel,
                    detail: "Your browsing data is protected.",
                    accent: true
                )

                summaryRow(
                    icon: appLockEnabled ? "lock.fill" : "lock.open",
                    title: appLockEnabled ? "App Lock enabled" : "App Lock off",
                    detail: appLockEnabled
                        ? "Touch ID or password required to open Searxly."
                        : "Enable it anytime in Settings → Privacy.",
                    accent: appLockEnabled
                )
            }
            .onboardingVisualReveal(revealed, reduceMotion: reduceMotion, delay: 0.12)
            .padding(.bottom, 24)

            // Micro tagline
            Text("PRIVATE  ·  YOURS  ·  LOCAL")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(3.0)
                .foregroundStyle(.tertiary.opacity(0.6))
                .onboardingVisualReveal(revealed, reduceMotion: reduceMotion, delay: 0.18)
        }
        .frame(maxWidth: 460, alignment: .center)
        .frame(maxWidth: .infinity)
        .onAppear { revealed = true }
    }

    private func summaryRow(icon: String, title: String, detail: String, accent: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent ? AnyShapeStyle(.primary.opacity(0.82)) : AnyShapeStyle(.tertiary))
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AdaptiveChrome.fill(colorScheme, dark: accent ? 0.12 : 0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    AdaptiveChrome.border(colorScheme, dark: accent ? 0.22 : 0.09),
                                    lineWidth: 1
                                )
                        )
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.06), radius: 6, y: 3)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent ? AnyShapeStyle(.primary.opacity(0.92)) : AnyShapeStyle(.secondary))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AdaptiveChrome.fill(colorScheme, dark: accent ? 0.09 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            AdaptiveChrome.border(colorScheme, dark: accent ? 0.16 : 0.08),
                            lineWidth: 1
                        )
                )
        )
    }
}
