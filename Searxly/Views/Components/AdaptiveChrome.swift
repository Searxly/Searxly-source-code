//
//  AdaptiveChrome.swift
//  Searxly
//
//  Semantic glass / border / fill colors that work in both light and dark mode.
//

import SwiftUI

enum AdaptiveChrome {
    /// Shared slim header + expanded sidebar top row height so chrome dividers meet cleanly.
    static let slimToolbarRowHeight: CGFloat = 40

    /// Deep premium canvas — home hero, sidebar, header, and main chrome in dark + glass mode.
    static let canvasDark = Color(red: 0.043, green: 0.043, blue: 0.051)

    /// Shared app background. Dark glass mode uses the premium near-black canvas; otherwise system window bg.
    static func appCanvas(_ scheme: ColorScheme, glassEnabled: Bool) -> Color {
        guard glassEnabled, scheme == .dark else {
            return Color(nsColor: .windowBackgroundColor)
        }
        return canvasDark
    }

    static func fill(_ scheme: ColorScheme, dark: Double, light: Double? = nil) -> Color {
        let lightOpacity = light ?? min(dark * 1.5, 0.14)
        return scheme == .dark ? Color.white.opacity(dark) : Color.primary.opacity(lightOpacity)
    }

    static func border(_ scheme: ColorScheme, dark: Double, light: Double? = nil) -> Color {
        let lightOpacity = light ?? min(dark * 1.8, 0.22)
        return scheme == .dark ? Color.white.opacity(dark) : Color.primary.opacity(lightOpacity)
    }

    static func divider(_ scheme: ColorScheme) -> Color {
        fill(scheme, dark: 0.06, light: 0.09)
    }

    static func panelTint(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.04) : Color.primary.opacity(0.03)
    }

    static func shadow(_ scheme: ColorScheme, darkOpacity: Double) -> Color {
        Color.black.opacity(scheme == .dark ? darkOpacity : darkOpacity * 0.5)
    }

    static func pressedOverlay(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.08) : Color.primary.opacity(0.06)
    }
}