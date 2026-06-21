//
//  OnboardingView.swift
//  Searxly
//
//  Public onboarding entry point. Implementation lives in Views/Onboarding/.
//

import SwiftUI

// MARK: - Public API

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @Binding var searxInstances: [SearXNGInstance]
    @Binding var currentInstanceID: UUID

    var glassEnabled: Bool = true
    var toolbarMaterial: Material = .ultraThinMaterial

    var body: some View {
        OnboardingFlow(
            hasCompletedOnboarding: $hasCompletedOnboarding,
            searxInstances: $searxInstances,
            currentInstanceID: $currentInstanceID,
            glassEnabled: glassEnabled
        )
    }
}


#Preview {
    OnboardingView(
        hasCompletedOnboarding: .constant(false),
        searxInstances: .constant([]),
        currentInstanceID: .constant(UUID()),
        glassEnabled: true
    )
}