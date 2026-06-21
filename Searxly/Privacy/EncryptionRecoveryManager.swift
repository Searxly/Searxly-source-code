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
}