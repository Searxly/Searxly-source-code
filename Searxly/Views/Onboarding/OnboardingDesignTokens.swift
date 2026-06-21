//
//  OnboardingDesignTokens.swift
//  Searxly
//

import SwiftUI

enum OnboardingStyle {
    static let stepCount = 4
    static let stepLabels = ["Welcome", "Local search", "Security", "Ready"]

    static let stepSpring = Animation.spring(response: 0.28, dampingFraction: 0.9)
    static let cardSpring = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let minTapHeight: CGFloat = 48
    static let contentMaxWidth: CGFloat = 620
    static let cardCornerRadius: CGFloat = 16
    static let buttonCardCornerRadius: CGFloat = 12
}

private struct OnboardingGlassEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var onboardingGlassEnabled: Bool {
        get { self[OnboardingGlassEnabledKey.self] }
        set { self[OnboardingGlassEnabledKey.self] = newValue }
    }
}

extension View {
    func onboardingGlassEnabled(_ enabled: Bool) -> some View {
        environment(\.onboardingGlassEnabled, enabled)
    }
}