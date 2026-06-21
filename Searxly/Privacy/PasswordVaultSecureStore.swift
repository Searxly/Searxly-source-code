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
import Security

nonisolated enum PasswordVaultSecureStore: Sendable {
    private static let service = "com.searxly.password-vault"

    // MARK: - Public API

    @discardableResult
    static func savePassword(_ password: String, for entryID: UUID) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }

        // Standard Keychain upsert: try update first to eliminate the delete→add window where
        // a crash between the two calls would silently lose the password.
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: entryID.uuidString
        ]
        let updateStatus = SecItemUpdate(match as CFDictionary,
                                         [kSecValueData as String: data] as CFDictionary)

        if updateStatus == errSecSuccess { return true }

        // Item doesn't exist yet (errSecItemNotFound) — add it.
        // Any other update error is unexpected; surface it and abort.
        guard updateStatus == errSecItemNotFound else {
            #if DEBUG
            print("[PasswordVaultSecureStore] update failed status=\(updateStatus) entry=\(entryID)")
            #endif
            return false
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: entryID.uuidString,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        #if DEBUG
        if addStatus != errSecSuccess {
            print("[PasswordVaultSecureStore] add failed status=\(addStatus) entry=\(entryID)")
        }
        #endif

        return addStatus == errSecSuccess
    }

    static func loadPassword(for entryID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: entryID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            #if DEBUG
            if status != errSecItemNotFound {
                print("[PasswordVaultSecureStore] load failed status=\(status) entry=\(entryID)")
            }
            #endif
            return nil
        }
        return password
    }

    @discardableResult
    static func deletePassword(for entryID: UUID) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: entryID.uuidString
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Removes every password item for this vault service.
    static func deleteAllPasswords() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}