//
//  DataEncryptor.swift
//  Searxly
//
//  Focused CryptoKit wrapper for encrypting/decrypting data blobs.
//  Uses AES-GCM with a simple versioned envelope for future compatibility.
//

import Foundation
import CryptoKit

enum DataEncryptor {

    private static let currentVersion: UInt8 = 1

    enum EncryptionError: Error, LocalizedError {
        case keyNotAvailable
        case decryptionFailed
        case invalidData
        case unsupportedVersion

        var errorDescription: String? {
            switch self {
            case .keyNotAvailable:
                return "Encryption key is not available in the Keychain."
            case .decryptionFailed:
                return "Failed to decrypt data. The data may be corrupted or the key may have changed."
            case .invalidData:
                return "The encrypted data is invalid or corrupted."
            case .unsupportedVersion:
                return "This encrypted data was created with a newer version of Searxly and cannot be read."
            }
        }
    }

    // MARK: - Public API

    /// Encrypts the given data using the provided key.
    /// Returns a versioned encrypted blob with a more robust header (magic + version).
    static func encrypt(_ plaintext: Data, using keyData: Data) throws -> Data {
        guard keyData.count == 32 else {
            throw EncryptionError.invalidData
        }

        let key = SymmetricKey(data: keyData)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)

        // New robust envelope: "SENC" (4 bytes magic) + [version: 1 byte] + [combined sealed box data]
        guard let combined = sealedBox.combined else {
            // AES.GCM combined output should never be nil under normal CryptoKit operation.
            // Throwing here prevents writing a header-only blob that would silently fail on decrypt.
            throw EncryptionError.invalidData
        }
        var result = Data("SENC".utf8)
        result.append(currentVersion)
        result.append(combined)

        return result
    }

    /// Decrypts a versioned encrypted blob using the provided key.
    /// Supports both old (single byte version) and new (SENC + version) formats.
    static func decrypt(_ encryptedData: Data, using keyData: Data) throws -> Data {
        guard encryptedData.count > 1 else {
            throw EncryptionError.invalidData
        }

        var version: UInt8
        var ciphertext: Data

        if encryptedData.prefix(4) == Data("SENC".utf8) {
            // New format: 4-byte magic + 1-byte version + AES-GCM combined (≥ 29 bytes)
            // Minimum: 5 header + 12 nonce + 16 tag + 1 ciphertext = 34 bytes total.
            guard encryptedData.count >= 34 else {
                throw EncryptionError.invalidData
            }
            version = encryptedData[4]
            ciphertext = encryptedData.dropFirst(5)
        } else {
            // Old format: 1-byte version + AES-GCM combined (≥ 29 bytes)
            // Minimum: 1 version + 12 nonce + 16 tag + 1 ciphertext = 30 bytes total.
            guard encryptedData.count >= 30 else {
                throw EncryptionError.invalidData
            }
            version = encryptedData[0]
            ciphertext = encryptedData.dropFirst()
        }

        guard version == currentVersion else {
            throw EncryptionError.unsupportedVersion
        }

        guard keyData.count == 32 else {
            throw EncryptionError.keyNotAvailable
        }

        let key = SymmetricKey(data: keyData)

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            let plaintext = try AES.GCM.open(sealedBox, using: key)
            return plaintext
        } catch {
            throw EncryptionError.decryptionFailed
        }
    }

    /// Convenience: Encrypt using the key currently stored in the Keychain.
    static func encryptWithStoredKey(_ plaintext: Data) throws -> Data {
        guard let key = KeychainManager.loadKey() else {
            throw EncryptionError.keyNotAvailable
        }
        return try encrypt(plaintext, using: key)
    }

    /// Convenience: Decrypt using the key currently stored in the Keychain.
    static func decryptWithStoredKey(_ encryptedData: Data) throws -> Data {
        guard let key = KeychainManager.loadKey() else {
            throw EncryptionError.keyNotAvailable
        }
        return try decrypt(encryptedData, using: key)
    }

    /// Generates a new 256-bit key suitable for AES-GCM.
    static func generateKey() -> Data {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0) }
    }
}
