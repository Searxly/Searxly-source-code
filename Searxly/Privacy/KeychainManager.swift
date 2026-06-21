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
import Security

enum KeychainManager {

    private static let service = "com.searxly.encryption"
    private static let account = "main-encryption-key"

    // MARK: - Public API

    /// Saves a 256-bit (32 byte) key to the Keychain.
    /// Uses update-or-add to preserve the existing ACL ("Always Allow" grant).
    /// Calling deleteKey() first would destroy that ACL and re-trigger the system prompt.
    @discardableResult
    static func saveKey(_ key: Data) -> Bool {
        guard key.count == 32 else {
            print("KeychainManager: Key must be exactly 32 bytes")
            return false
        }

        let findQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateAttributes: [String: Any] = [
            kSecValueData as String: key,
        ]
        let updateStatus = SecItemUpdate(findQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            print("KeychainManager: Encryption key updated (ACL preserved)")
            return true
        }

        // Item doesn't exist yet — add it fresh.
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            print("KeychainManager: Encryption key saved successfully")
            return true
        } else {
            print("KeychainManager: Failed to save key. Status: \(addStatus)")
            return false
        }
    }

    /// Loads the encryption key from the Keychain.
    /// Returns nil if the key does not exist or cannot be accessed (e.g. device locked).
    static func loadKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let keyData = result as? Data,
              keyData.count == 32 else {
            if status != errSecItemNotFound {
                print("KeychainManager: Failed to load key. Status: \(status)")
            }
            return nil
        }

        return keyData
    }

    /// Deletes the encryption key from the Keychain.
    @discardableResult
    static func deleteKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        } else {
            print("KeychainManager: Failed to delete key. Status: \(status)")
            return false
        }
    }

    /// Checks whether a key item exists in the Keychain (without reading the secret).
    static func keyExists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
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
        print("KeychainManager: !!! DANGER - Encryption recovery key was exported. This key can decrypt all user data.")
        return keyData.base64EncodedString()
    }

    /// Imports a key from a base64 recovery code (for future recovery flows).
    @discardableResult
    static func importKeyFromRecoveryCode(_ base64String: String) -> Bool {
        guard let keyData = Data(base64Encoded: base64String),
              keyData.count == 32 else {
            print("KeychainManager: Invalid recovery code format")
            return false
        }
        print("KeychainManager: Importing encryption key from recovery code. This will replace the current key.")
        return saveKey(keyData)
    }
}
