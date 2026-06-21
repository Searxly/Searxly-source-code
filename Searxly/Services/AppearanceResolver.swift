//
//  AppearanceResolver.swift
//  Searxly
//
//  Resolves the effective color scheme for the app. Never passes nil to
//  preferredColorScheme — that breaks when switching Light → System on a dark Mac.
//

import AppKit
import SwiftUI

enum AppearanceResolver {
    /// macOS system appearance (independent of any in-app override).
    static var systemColorScheme: ColorScheme {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .dark : .light
    }

    static func resolved(mode: AppearanceMode, system: ColorScheme) -> ColorScheme {
        switch mode {
        case .system: return system
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    static func resolved(modeRaw: String, system: ColorScheme) -> ColorScheme {
        resolved(mode: AppearanceMode(rawValue: modeRaw) ?? .system, system: system)
    }

    /// Posted when the user changes macOS appearance (Light/Dark/Auto).
    static var systemAppearanceDidChange: NotificationCenter.Publisher {
        DistributedNotificationCenter.default().publisher(
            for: Notification.Name("AppleInterfaceThemeChangedNotification")
        )
    }
}