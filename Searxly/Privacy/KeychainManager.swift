//
//  KeychainManager.swift
//  Searxly
//
//  Thin, focused wrapper around the Keychain for storing the encryption key.
//  Designed for safety and clarity. No business logic here.
//
//  Key protection: kSecAttrAccessibleWhenUnlockedThisDeviceOnly (device-only, not iCloud-synced).
//  App Lock is the user-facing gate; per-item SecAccessControl .userPresence requires
//  entitlements this app does not declare on macOS (errSecMissingEntitlement).
//

import Foundation
import os
import Security

enum KeychainManager {

    private static let service = "com.searxly.encryption"
    private static let account = "main-encryption-key"

    // Use the data-protection keychain (no signature-ACL prompts) when available; otherwise legacy.
    private static var dp: Bool { KeychainDataProtection.isAvailable }

    private static func baseQuery(dataProtection: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if dataProtection { q[kSecUseDataProtectionKeychain as String] = true }
        return q
    }

    // MARK: - Public API

    /// Saves a 256-bit (32 byte) key to the Keychain (data-protection keychain when available).
    /// Uses update-or-add so a prior item's grant is preserved.
    @discardableResult
    static func saveKey(_ key: Data) -> Bool {
        guard key.count == 32 else {
            Log.security.error("KeychainManager: key must be exactly 32 bytes")
            return false
        }

        // Write to the data-protection keychain when it's usable (prompt-free on a correctly-signed
        // build) AND always keep a copy in the legacy keychain. We deliberately NEVER delete a copy:
        // a key that exists in only one store gets orphaned the moment data-protection availability
        // flips between builds (e.g. a signing / entitlement / team change) — which is exactly how a
        // user gets locked out of their encrypted data. Two device-only copies cost nothing and keep
        // the key reachable no matter which store the running build can see.
        var savedAny = false
        if dp { savedAny = upsert(key, dataProtection: true) }
        if upsert(key, dataProtection: false) { savedAny = true }
        if !savedAny { Log.security.error("KeychainManager: failed to save key to any keychain") }
        return savedAny
    }

    /// Update-or-add the key into one keychain store. Update first so an existing item's ACL grant is
    /// preserved (avoids re-triggering the legacy signature prompt).
    @discardableResult
    private static func upsert(_ key: Data, dataProtection: Bool) -> Bool {
        let find = baseQuery(dataProtection: dataProtection)
        if SecItemUpdate(find as CFDictionary, [kSecValueData as String: key] as CFDictionary) == errSecSuccess {
            return true
        }
        var add = baseQuery(dataProtection: dataProtection)
        add[kSecValueData as String] = key
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// Loads the encryption key from the Keychain.
    /// Returns nil if the key does not exist or cannot be accessed (e.g. device locked).
    static func loadKey() -> Data? {
        // Try BOTH stores regardless of the probe, so a key written under one is never orphaned when
        // data-protection availability changes. Prefer data-protection (no signature-ACL prompt on a
        // correctly-signed build); fall back to legacy. Querying the data-protection keychain when the
        // entitlement is absent just returns "not found", so trying it first is always safe.
        if let k = rawLoad(dataProtection: true) { return k }
        if let k = rawLoad(dataProtection: false) {
            // Mirror into the data-protection keychain when usable so future reads are prompt-free —
            // but keep the legacy copy as permanent lockout insurance (never delete it).
            if dp { _ = upsert(k, dataProtection: true) }
            return k
        }
        return nil
    }

    private static func rawLoad(dataProtection: Bool) -> Data? {
        var query = baseQuery(dataProtection: dataProtection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let keyData = result as? Data, keyData.count == 32 else {
            return nil
        }
        return keyData
    }

    /// Deletes the encryption key from the Keychain (both keychains, so a delete is total).
    @discardableResult
    static func deleteKey() -> Bool {
        var ok = true
        if dp {
            let s = SecItemDelete(baseQuery(dataProtection: true) as CFDictionary)
            ok = (s == errSecSuccess || s == errSecItemNotFound)
        }
        let s2 = SecItemDelete(baseQuery(dataProtection: false) as CFDictionary)
        return ok && (s2 == errSecSuccess || s2 == errSecItemNotFound)
    }

    /// Checks whether a key item exists in the Keychain (without reading the secret).
    static func keyExists() -> Bool {
        func exists(dataProtection: Bool) -> Bool {
            var q = baseQuery(dataProtection: dataProtection)
            q[kSecReturnData as String] = false
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
        }
        return exists(dataProtection: true) || exists(dataProtection: false)
    }

    // MARK: - Recovery Support (Phase 2)

    /// Exports the current encryption key as a base64-encoded string.
    ///
    /// ⚠️  EXTREME DANGER ⚠️
    /// This is the literal 256-bit AES key. Anyone who obtains this string can decrypt
    /// all of your encrypted Searxly data (history, bookmarks, tabs, etc.).
    ///
    /// - Treat this exactly like a master password.
    /// - Never store it in plain text, email, notes, or cloud services unless you fully understand the risk.
    /// - This feature exists for advanced users doing manual backups only.
    static func exportKeyAsRecoveryCode() -> String? {
        guard let keyData = loadKey() else {
            return nil
        }
        // Audit event (persisted): the action is logged, never the key itself.
        Log.security.notice("KeychainManager: encryption recovery key was exported (can decrypt all user data)")
        return keyData.base64EncodedString()
    }

    /// Imports a key from a base64 recovery code (for future recovery flows).
    @discardableResult
    static func importKeyFromRecoveryCode(_ base64String: String) -> Bool {
        guard let keyData = Data(base64Encoded: base64String),
              keyData.count == 32 else {
            Log.security.error("KeychainManager: invalid recovery code format")
            return false
        }
        Log.security.notice("KeychainManager: importing encryption key from recovery code (replaces current key)")
        return saveKey(keyData)
    }
}
