//
//  HomeAmbientBackground.swift
//  Searxly
//
//  Shared starfield + sunlight glow behind the pure home state (header + hero).
//

import SwiftUI

struct HomeAmbientBackground: View {
    let glassEnabled: Bool
    let homeStarsEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AdaptiveChrome.appCanvas(colorScheme, glassEnabled: glassEnabled)
                .ignoresSafeArea()

            if glassEnabled {
                RadialGradient(
                    colors: [
                        AdaptiveChrome.fill(colorScheme, dark: 0.06, light: 0.04),
                        .clear
                    ],
                    center: .center,
                    startRadius: 60,
                    endRadius: 520
                )
                .allowsHitTesting(false)

                RadialGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.09 : 0.14),
                        Color.white.opacity(colorScheme == .dark ? 0.035 : 0.05),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.30),
                    startRadius: 24,
                    endRadius: 400
                )
                .allowsHitTesting(false)
            }

            if homeStarsEnabled {
                HomeStarfield(enabled: true)
            }

            if glassEnabled {
                RadialGradient(
                    colors: [
                        .clear,
                        Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06)
                    ],
                    center: .center,
                    startRadius: 280,
                    endRadius: 720
                )
                .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }
}