//
//  BackupManager.swift
//  Searxly
//
//  Encrypted backup and restore for the entire app state.
//  Produces a single portable .searxlybackup file that contains the AppData
//  (history, bookmarks, instances, etc.) plus optionally the encryption key,
//  all protected by a strong user password.
//
//  This is the recommended way to migrate or back up Searxly.
//

import Foundation
import CryptoKit
import CommonCrypto

enum BackupManager {

    enum BackupError: LocalizedError {
        case noData
        case invalidPassword
        case corruptedBackup
        case keyMissing
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .noData: return "No data available to back up."
            case .invalidPassword: return "The password was incorrect or the backup is corrupted."
            case .corruptedBackup: return "This backup file is corrupted or was created by a newer version of Searxly."
            case .keyMissing: return "Encryption is enabled but no key is available in the Keychain."
            case .writeFailed: return "Failed to write the backup file."
            }
        }
    }

    // MARK: - Public API

    /// Creates an encrypted backup file at the given URL.
    /// - Parameter destination: Where to save the .searxlybackup file.
    /// - Parameter password: Strong password chosen by the user.
    /// - Parameter includeKey: Whether to also embed the current encryption key (allows full restore including key).
    static func createBackup(to destination: URL, password: String, includeKey: Bool = true) throws {
        let appData = Persistence.load()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let dataBlob = try encoder.encode(appData)

        var keyData: Data?
        if includeKey, let key = KeychainManager.loadKey() {
            keyData = key
        }

        let backup = EncryptedBackup(
            version: 1,
            timestamp: Date(),
            appData: dataBlob,
            encryptionKey: keyData
        )

        let payload = try backup.encryptedPayload(using: password)
        try payload.write(to: destination, options: .atomic)
    }

    /// Restores from an encrypted backup file.
    /// - Parameter source: The .searxlybackup file.
    /// - Parameter password: The password used when the backup was created.
    /// - Returns: Whether the encryption key was also restored.
    @discardableResult
    static func restore(from source: URL, password: String) throws -> Bool {
        let payload = try Data(contentsOf: source)

        let backup = try EncryptedBackup.decrypted(from: payload, using: password)

        // Restore the main data
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restoredData = try decoder.decode(AppData.self, from: backup.appData)

        // Write it through the normal path (respects current encryption setting)
        Persistence.save(restoredData)
        EncryptionRecoveryManager.shared.clearRecoveryState()

        var keyWasRestored = false

        // Optionally restore the encryption key into Keychain
        if let embeddedKey = backup.encryptionKey {
            _ = KeychainManager.saveKey(embeddedKey)
            keyWasRestored = true

            // If the user had encryption off, we can turn it on now
            if !EncryptedDataStore.isEncryptionEnabled() {
                EncryptedDataStore.setEncryptionEnabled(true)
                PrivacyManager.shared.forceSetDataEncryptionEnabled(true)
            }
        }

        return keyWasRestored
    }

    // MARK: - Internal encrypted container

    private struct EncryptedBackup: Codable {
        let version: Int
        let timestamp: Date
        let appData: Data
        let encryptionKey: Data?   // optional

        /// Encrypts the backup using a password (PBKDF2-HMAC-SHA256 + AES-GCM).
        func encryptedPayload(using password: String) throws -> Data {
            var saltBytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else {
                throw BackupManager.BackupError.writeFailed
            }
            let salt = Data(saltBytes)
            let key = try Self.deriveKey(from: password, salt: salt)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let plaintext = try encoder.encode(self)

            let sealed = try AES.GCM.seal(plaintext, using: key)

            // Format: "SBKP" + version (1 byte) + salt (16) + combined sealed box
            var result = Data("SBKP".utf8)
            result.append(1) // version
            result.append(salt)
            result.append(sealed.combined ?? Data())

            return result
        }

        static func decrypted(from payload: Data, using password: String) throws -> EncryptedBackup {
            guard payload.count > 22,
                  payload.prefix(4) == Data("SBKP".utf8),
                  payload[4] == 1 else {
                throw BackupError.corruptedBackup
            }

            let salt = payload[5..<21]
            let ciphertext = payload[21...]

            let key = try Self.deriveKey(from: password, salt: salt)

            do {
                let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
                let plaintext = try AES.GCM.open(sealedBox, using: key)

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(EncryptedBackup.self, from: plaintext)
            } catch {
                throw BackupError.invalidPassword
            }
        }

        private static func deriveKey(from password: String, salt: Data) throws -> SymmetricKey {
            let passwordData = Data(password.utf8)
            let derived = try PBKDF2(
                password: passwordData,
                salt: salt,
                iterations: 150_000,
                keyLength: 32
            )
            return SymmetricKey(data: derived)
        }
    }
}

// Minimal PBKDF2 implementation using CommonCrypto (via Security framework on Apple platforms)
private func PBKDF2(password: Data, salt: Data, iterations: Int, keyLength: Int) throws -> Data {
    var derivedKey = Data(count: keyLength)
    let result = derivedKey.withUnsafeMutableBytes { derivedBytes in
        password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.baseAddress!.assumingMemoryBound(to: Int8.self),
                    password.count,
                    saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    derivedBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    keyLength
                )
            }
        }
    }
    guard result == kCCSuccess else {
        throw BackupManager.BackupError.corruptedBackup  // Re-use existing error; derivation failure == unrecoverable for this backup
    }
    return derivedKey
}
