//
//  Localization.swift
//  Searxly
//
//  Loads strings from the best matching .lproj for the Mac's system language.
//  Falls back to English when no translation bundle exists.
//

import Foundation

enum Localization {
    /// Language used for UI strings (supported .lproj or English).
    static var currentLanguage: AppLanguage { AppLanguage.current }

    /// Language code sent to SearXNG — follows system even without a UI translation.
    static var searchLanguageCode: String { AppLanguage.systemSearchLanguageCode }

    /// Bundle for localized strings, walking the user's preferred languages.
    static var bundle: Bundle {
        for localeID in Locale.preferredLanguages {
            let base = localeID.split(separator: "-").first.map(String.init) ?? localeID
            if let path = Bundle.main.path(forResource: base, ofType: "lproj"),
               let langBundle = Bundle(path: path) {
                return langBundle
            }
        }
        return .main
    }

    static func string(_ key: String, defaultValue: String? = nil) -> String {
        let value = bundle.localizedString(forKey: key, value: defaultValue, table: nil)
        if value == key, let fallback = defaultValue {
            return fallback
        }
        return value
    }

    /// One-time cleanup for installs that used the old in-app language picker.
    static func migrateAwayFromManualLanguageOverride() {
        UserDefaults.standard.removeObject(forKey: "preferredAppLanguage")
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    }
}

// MARK: - SwiftUI convenience

import SwiftUI

extension Text {
    init(localized key: String, defaultValue: String? = nil) {
        self.init(Localization.string(key, defaultValue: defaultValue))
    }
}

extension LocalizedStringKey {
    static func app(_ key: String) -> LocalizedStringKey {
        LocalizedStringKey(key)
    }
}