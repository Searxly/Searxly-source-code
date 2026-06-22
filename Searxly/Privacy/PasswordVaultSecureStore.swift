//
//  PasswordVaultSecureStore.swift
//  Searxly
//
//  Keychain storage for password vault secrets. One generic-password item per entry ID.
//  Uses kSecAttrAccessibleWhenUnlockedThisDeviceOnly (device-only, not iCloud-synced).
//  Vault unlock (Touch ID / passphrase) is the user-facing gate; per-item userPresence
//  SecAccessControl requires entitlements this app does not declare on macOS.
//

import Foundation
import os
import Security

nonisolated enum PasswordVaultSecureStore: Sendable {
    private static let service = "com.searxly.password-vault"

    // Use the data-protection keychain (no signature-ACL prompts) when available; otherwise legacy.
    private static var dp: Bool { KeychainDataProtection.isAvailable }

    private static func baseQuery(entryID: UUID, dataProtection: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: entryID.uuidString,
        ]
        if dataProtection { q[kSecUseDataProtectionKeychain as String] = true }
        return q
    }

    // MARK: - Public API

    @discardableResult
    static func savePassword(_ password: String, for entryID: UUID) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }

        // Standard Keychain upsert: try update first to eliminate the delete→add window where
        // a crash between the two calls would silently lose the password.
        let match = baseQuery(entryID: entryID, dataProtection: dp)
        let updateStatus = SecItemUpdate(match as CFDictionary,
                                         [kSecValueData as String: data] as CFDictionary)

        if updateStatus == errSecSuccess { return true }

        // Item doesn't exist yet (errSecItemNotFound) — add it.
        // Any other update error is unexpected; surface it and abort.
        guard updateStatus == errSecItemNotFound else {
            #if DEBUG
            Log.security.error("[PasswordVaultSecureStore] update failed status=\(updateStatus) entry=\(entryID)")
            #endif
            return false
        }

        var addQuery = baseQuery(entryID: entryID, dataProtection: dp)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        addQuery[kSecAttrSynchronizable as String] = false
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        #if DEBUG
        if addStatus != errSecSuccess {
            Log.security.error("[PasswordVaultSecureStore] add failed status=\(addStatus) entry=\(entryID)")
        }
        #endif

        if addStatus == errSecSuccess {
            // Drop any legacy copy so it never prompts again.
            if dp { SecItemDelete(baseQuery(entryID: entryID, dataProtection: false) as CFDictionary) }
            return true
        }
        return false
    }

    static func loadPassword(for entryID: UUID) -> String? {
        if dp {
            if let pw = rawLoad(entryID: entryID, dataProtection: true) { return pw }
            // Migrate a legacy-keychain entry into the data-protection keychain (one-time).
            if let legacy = rawLoad(entryID: entryID, dataProtection: false) {
                migrate(legacy, entryID: entryID)
                return legacy
            }
            return nil
        }
        return rawLoad(entryID: entryID, dataProtection: false)
    }

    private static func rawLoad(entryID: UUID, dataProtection: Bool) -> String? {
        var query = baseQuery(entryID: entryID, dataProtection: dataProtection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        return password
    }

    private static func migrate(_ password: String, entryID: UUID) {
        guard let data = password.data(using: .utf8) else { return }
        var add = baseQuery(entryID: entryID, dataProtection: true)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess || status == errSecDuplicateItem {
            SecItemDelete(baseQuery(entryID: entryID, dataProtection: false) as CFDictionary)
        }
    }

    @discardableResult
    static func deletePassword(for entryID: UUID) -> Bool {
        var ok = true
        if dp {
            let s = SecItemDelete(baseQuery(entryID: entryID, dataProtection: true) as CFDictionary)
            ok = (s == errSecSuccess || s == errSecItemNotFound)
        }
        let s2 = SecItemDelete(baseQuery(entryID: entryID, dataProtection: false) as CFDictionary)
        return ok && (s2 == errSecSuccess || s2 == errSecItemNotFound)
    }

    /// Removes every password item for this vault service (both keychains).
    static func deleteAllPasswords() {
        func wipe(dataProtection: Bool) {
            var q: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
            ]
            if dataProtection { q[kSecUseDataProtectionKeychain as String] = true }
            SecItemDelete(q as CFDictionary)
        }
        if dp { wipe(dataProtection: true) }
        wipe(dataProtection: false)
    }
}