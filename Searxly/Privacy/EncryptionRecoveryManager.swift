//
//  EncryptionRecoveryManager.swift
//  Searxly
//
//  Tracks when encrypted AppData.json cannot be decrypted and gates the main UI
//  behind a blocking recovery screen (recovery code or encrypted backup restore).
//

import Foundation

@MainActor
@Observable
final class EncryptionRecoveryManager {
    static let shared = EncryptionRecoveryManager()

    private(set) var isRecoveryRequired = false
    private(set) var errorMessage: String?

    private init() {}

    func markDecryptionFailed(_ error: DataEncryptor.EncryptionError) {
        isRecoveryRequired = true
        errorMessage = error.localizedDescription
    }

    func clearRecoveryState() {
        isRecoveryRequired = false
        errorMessage = nil
    }

    /// Imports a base64 recovery code into the Keychain and verifies the on-disk data decrypts.
    @discardableResult
    func recoverWithRecoveryCode(_ code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard KeychainManager.importKeyFromRecoveryCode(trimmed) else {
            return false
        }

        switch EncryptedDataStore.loadDetailed() {
        case .success:
            clearRecoveryState()
            PrivacyManager.shared.syncEncryptionStateFromDisk()
            NotificationCenter.default.post(name: .encryptionRecoverySucceeded, object: nil)
            return true
        case .decryptionFailed, .decodeFailed:
            return false
        case .missingFile:
            clearRecoveryState()
            PrivacyManager.shared.syncEncryptionStateFromDisk()
            NotificationCenter.default.post(name: .encryptionRecoverySucceeded, object: nil)
            return true
        }
    }

    /// Restores from a .searxlybackup file without wiping the encrypted blob first.
    func recoverFromBackup(at url: URL, password: String) throws {
        _ = try BackupManager.restore(from: url, password: password)
        clearRecoveryState()
        PrivacyManager.shared.syncEncryptionStateFromDisk()
        NotificationCenter.default.post(name: .encryptionRecoverySucceeded, object: nil)
    }

    /// Last-resort escape hatch: erase the unreadable local data and start the app fresh.
    ///
    /// For when the encryption key is permanently unavailable (orphaned by an app-identity change) and
    /// the user has no recovery code or backup. Destroys local browsing history / bookmarks / instances /
    /// settings; does NOT touch the wallet seed or saved passwords (separate stores). Also drops the
    /// orphaned Keychain key so a clean encryption key can be generated if the user re-enables encryption.
    func startFresh() {
        EncryptedDataStore.eraseLocalData()
        KeychainManager.deleteKey()
        clearRecoveryState()
        PrivacyManager.shared.syncEncryptionStateFromDisk()
        NotificationCenter.default.post(name: .encryptionRecoverySucceeded, object: nil)
    }
}