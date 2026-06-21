//
//  AppLanguage.swift
//  Searxly
//
//  Resolves the active language from macOS Language & Region settings.
//  Used for SearXNG search bias (language=...) and .lproj bundle lookup.
//

import Foundation

struct AppLanguage {
    /// ISO 639-1 language code (e.g. "en", "fr", "de").
    let code: String

    /// Active language derived from the user's system preference list.
    static var current: AppLanguage {
        AppLanguage(code: resolvedSystemCode())
    }

    /// Walk preferred languages until we find a supported .lproj, otherwise English.
    private static func resolvedSystemCode() -> String {
        for localeID in Locale.preferredLanguages {
            let base = localeID.split(separator: "-").first.map(String.init) ?? localeID
            if Bundle.main.path(forResource: base, ofType: "lproj") != nil {
                return base
            }
        }
        return "en"
    }

    // MARK: - Search language override (set from Settings → Search → Language)

    static let searchLanguageOverrideKey = "searchLanguageOverride"

    /// An explicit per-app search language the user set in Searxly's own settings.
    /// When set, this takes priority over the system locale for all SearXNG queries.
    /// `nil` means "follow the system" (macOS Language & Region).
    static var searchLanguageOverride: String? {
        get {
            let v = UserDefaults.standard.string(forKey: searchLanguageOverrideKey) ?? ""
            return v.isEmpty ? nil : v
        }
        set {
            if let code = newValue, !code.isEmpty {
                UserDefaults.standard.set(code, forKey: searchLanguageOverrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: searchLanguageOverrideKey)
            }
        }
    }

    /// Full locale code sent to SearXNG (e.g. "en-US", "fr-FR").
    /// Priority: explicit in-app override → macOS per-app language → system default.
    /// Keeping the country suffix matters: search engines like Bing use it to pick
    /// a result region, which overrides IP-based geo-targeting. Returning just "en"
    /// leaves the country ambiguous and lets a French IP pull French content.
    static var systemSearchLanguageCode: String {
        // 1. User's explicit override from Searxly's own settings takes top priority.
        if let override = searchLanguageOverride {
            return override
        }
        // 2. System / macOS per-app language (respects System Settings → Language & Region).
        guard let preferred = Locale.preferredLanguages.first else { return "en-US" }
        // Normalize to the format SearXNG expects: lowercase-UPPERCASE (e.g. "en-US")
        let parts = preferred.split(separator: "-", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return "\(parts[0].lowercased())-\(parts[1].uppercased())"
        }
        return parts[0].lowercased()
    }
}