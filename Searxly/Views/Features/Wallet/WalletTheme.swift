//
//  WalletTheme.swift
//  Searxly
//
//  Single source of truth for the wallet's look: a premium, monochrome "black" palette that
//  matches the rest of Searxly (AdaptiveChrome.canvasDark). Every wallet panel, sheet, card,
//  field, and stroke draws from these tokens so the whole feature reads as one cohesive surface.
//
//  Brand rule (see the black_white memory): monochrome only. Color is reserved for *meaning* —
//  green for positive / live, red for negative / destructive, amber for a genuine warning.
//

import SwiftUI

enum WalletTheme {

    // MARK: - Canvas (sheet / panel backgrounds)

    /// The deep premium near-black used for the home hero, sidebar, and main chrome. Reusing the
    /// exact app canvas makes the wallet feel native to Searxly rather than a bolted-on dark sheet.
    static let canvas = Color(red: 0.043, green: 0.043, blue: 0.051)
    /// Very slightly lifted canvas for a band that needs to separate from the base (e.g. the
    /// balance summary) without a hard divider.
    static let canvasRaised = Color(red: 0.062, green: 0.062, blue: 0.070)

    // MARK: - Surfaces (cards, rows, inputs) — translucent so the canvas reads through

    static let surface        = Color.white.opacity(0.05)    // cards / grouped rows
    static let surfaceField    = Color.white.opacity(0.06)    // text fields / inputs
    static let surfaceStrong   = Color.white.opacity(0.08)    // secondary buttons / chips
    static let surfaceSelected = Color.white.opacity(0.14)    // selected segment / chip

    // MARK: - Lines

    static let hairline       = Color.white.opacity(0.08)    // card strokes
    static let hairlineStrong = Color.white.opacity(0.14)    // emphasized strokes / focused field
    static let divider        = Color.white.opacity(0.07)

    // MARK: - Text (monochrome ramp)

    static let textPrimary    = Color.white
    static let textSecondary  = Color(white: 0.62)
    static let textTertiary   = Color(white: 0.42)
    static let textFaint      = Color(white: 0.30)

    // MARK: - Semantic (the only color allowed, and only for meaning)

    static let positive = SERPDesign.accentGreen
    static let negative = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let warning  = Color(red: 1.0, green: 0.62, blue: 0.28)

    // MARK: - Geometry

    static let radiusCard: CGFloat  = 18
    static let radiusInner: CGFloat = 12
    static let radiusField: CGFloat = 10

    // MARK: - Primary (white) action button helper

    /// The wallet's primary CTA is a solid white pill with black text — the consistent
    /// "confirm / connect / send" affordance across every sheet.
    static func primaryFill(enabled: Bool) -> Color { enabled ? .white : Color.white.opacity(0.12) }
    static func primaryText(enabled: Bool) -> Color { enabled ? .black : Color(white: 0.34) }
}

// MARK: - Reusable card background

extension View {
    /// Standard wallet card: a flat translucent surface, continuous corners, no border (Phantom-style).
    func walletCard(radius: CGFloat = WalletTheme.radiusCard) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(WalletTheme.surface))
    }
}
