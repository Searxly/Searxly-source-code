//
//  KeychainDataProtection.swift
//  Searxly
//
//  Shared capability check for the macOS **data-protection keychain** (kSecUseDataProtectionKeychain).
//
//  Why: the legacy file-based keychain gates each item by an ACL tied to the app's CODE SIGNATURE.
//  Sandboxed dev / ad-hoc builds get a fresh signature every rebuild, so macOS re-prompts
//  ("Searxly wants to use your confidential information…") for each item on every launch. The
//  data-protection keychain instead scopes items to the sandboxed app's own access group, so there
//  is no per-signature prompt at all.
//
//  We probe availability once (some signing setups lack the entitlement) and fall back to the legacy
//  keychain if it isn't usable, so storage never regresses. Each store migrates its existing legacy
//  items into the data-protection keychain transparently on first read.
//
//  (WalletKeychain has its own equivalent probe; this shared helper backs the non-wallet stores.)
//

import Foundation
import os
import Security

// `nonisolated`: pure keychain capability probe with no actor state; used from nonisolated stores
// (PasswordVaultSecureStore, etc.) under the module's default-MainActor isolation.
nonisolated enum KeychainDataProtection {

    /// Probed once. True → use the data-protection keychain everywhere (no signature-ACL prompts).
    static let isAvailable: Bool = probe()

    private static func probe() -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.searxly.keychain-dp-probe",
            kSecAttrAccount as String: "probe",
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data([0x01])
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess {
            SecItemDelete(base as CFDictionary)
            return true
        }
        #if DEBUG
        Log.security.error("[KeychainDataProtection] unavailable (OSStatus \(status)); using legacy keychain.")
        #endif
        return false
    }
}
