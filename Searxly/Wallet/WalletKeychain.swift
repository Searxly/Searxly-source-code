//
//  WalletKeychain.swift
//  Searxly
//
//  Stores the encrypted seed phrase in the macOS Keychain.
//
//  Security model:
//   - Seed is AES-GCM encrypted with a key derived from the user's PIN via PBKDF2-SHA256
//     (200k iterations) using a per-wallet RANDOM salt (prevents precomputed/rainbow attacks
//     across wallets).
//   - A second copy of the seed is encrypted with a key derived from the high-entropy recovery
//     code, so "forgot PIN" can genuinely re-key the seed to a new PIN.
//   - All items are device-only (kSecAttrAccessibleWhenUnlockedThisDeviceOnly), never iCloud-synced.
//

import Foundation
import Security
import CryptoKit
import CommonCrypto
import LocalAuthentication

enum WalletKeychain {

    private static let service = "com.myrhex.Searxly.wallet"
    private static let seedAccount = "wallet-seed"
    private static let recoverySeedAccount = "wallet-recovery-seed"
    private static let saltAccount = "wallet-kdf-salt"
    private static let biometricPINAccount = "wallet-biometric-pin"
    private static let connectedSitesAccount = "wallet-connected-sites"
    private static let addressAccount = "wallet-address"
    private static let zeroExKeyAccount = "wallet-0x-api-key"
    private static let basescanKeyAccount = "wallet-basescan-api-key"
    private static let activityAccount = "wallet-activity"
    private static let accountsAccount = "wallet-accounts"
    private static let siteAccountsAccount = "wallet-site-accounts"
    private static let rotationAccountsAccount = "wallet-rotation-accounts"
    private static let importedKeysAccount = "wallet-imported-keys"
    private static let contactsAccount = "wallet-contacts"
    private static let portfolioHistoryAccount = "wallet-portfolio-history"

    private static let pbkdf2Rounds: UInt32 = 200_000

    // MARK: - Seed (PIN-encrypted)

    @discardableResult
    static func saveSeed(_ words: [String], pin: String) -> Bool {
        guard let phraseData = words.joined(separator: " ").data(using: .utf8) else { return false }
        let key = deriveKey(from: pin, salt: loadOrCreateSalt())
        guard let encrypted = try? encryptAES(phraseData, key: key) else { return false }
        return saveItem(encrypted, account: seedAccount)
    }

    static func loadSeed(pin: String) -> [String]? {
        guard let encrypted = loadItem(account: seedAccount) else { return nil }
        if let salt = loadSalt() {
            return decryptSeed(encrypted, secret: pin, salt: salt)
        }
        // Legacy wallet (created before per-wallet salts): decrypt with the old fixed-salt/100k KDF,
        // then transparently migrate it to the new random-salt/200k KDF so it's upgraded going forward.
        if let words = legacyDecryptSeed(encrypted, pin: pin) {
            saveSeed(words, pin: pin)
            return words
        }
        return nil
    }

    private static func legacyDecryptSeed(_ encrypted: Data, pin: String) -> [String]? {
        let salt = Data("searxly-wallet-v1".utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        salt.withUnsafeBytes { saltPtr in
            _ = CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2), pin, pin.utf8.count,
                saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 100_000, &derived, 32)
        }
        guard let decrypted = try? decryptAES(encrypted, key: Data(derived)),
              let phrase = String(data: decrypted, encoding: .utf8) else { return nil }
        let words = phrase.components(separatedBy: " ").filter { !$0.isEmpty }
        return words.isEmpty ? nil : words
    }

    static func deleteSeed() {
        // Wipe every wallet keychain item so nothing lingers after a delete.
        [seedAccount, recoverySeedAccount, saltAccount, biometricPINAccount,
         connectedSitesAccount, addressAccount, activityAccount,
         accountsAccount, siteAccountsAccount, rotationAccountsAccount, importedKeysAccount,
         contactsAccount, portfolioHistoryAccount, zeroExKeyAccount, basescanKeyAccount].forEach(deleteItem)
    }

    // MARK: - Address book (saved recipient contacts — who you pay is private)

    static func saveContacts(_ contacts: [WalletContact]) {
        guard let data = try? JSONEncoder().encode(contacts) else { return }
        _ = saveItem(data, account: contactsAccount)
    }

    static func loadContacts() -> [WalletContact] {
        guard let data = loadItem(account: contactsAccount),
              let contacts = try? JSONDecoder().decode([WalletContact].self, from: data) else { return [] }
        return contacts
    }

    // MARK: - HD accounts (index + address + label; addresses are public but kept device-only)

    static func saveAccounts(_ accounts: [WalletAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        _ = saveItem(data, account: accountsAccount)
    }

    static func loadAccounts() -> [WalletAccount] {
        guard let data = loadItem(account: accountsAccount),
              let accounts = try? JSONDecoder().decode([WalletAccount].self, from: data) else { return [] }
        return accounts
    }

    /// Per-dApp rotation accounts — a pool of hidden HD accounts (high index range) each assigned to
    /// one site so connected dApps can't be cross-linked to a single on-chain identity.
    static func saveRotationAccounts(_ accounts: [WalletAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        _ = saveItem(data, account: rotationAccountsAccount)
    }

    static func loadRotationAccounts() -> [WalletAccount] {
        guard let data = loadItem(account: rotationAccountsAccount),
              let accounts = try? JSONDecoder().decode([WalletAccount].self, from: data) else { return [] }
        return accounts
    }

    // MARK: - Imported private keys (one per imported account, encrypted under the PIN like the seed)

    /// Stores the full map of imported account index → raw 32-byte private key, encrypted with the
    /// PIN-derived key (same AES-GCM + per-wallet salt as the seed). Re-encrypts the whole blob.
    @discardableResult
    static func saveImportedKeys(_ keysByIndex: [Int: Data], pin: String) -> Bool {
        let map = keysByIndex.reduce(into: [String: String]()) { $0[String($1.key)] = $1.value.map { String(format: "%02x", $0) }.joined() }
        guard let json = try? JSONSerialization.data(withJSONObject: map) else { return false }
        let key = deriveKey(from: pin, salt: loadOrCreateSalt())
        guard let encrypted = try? encryptAES(json, key: key) else { return false }
        return saveItem(encrypted, account: importedKeysAccount)
    }

    static func loadImportedKeys(pin: String) -> [Int: Data] {
        guard let encrypted = loadItem(account: importedKeysAccount), let salt = loadSalt(),
              let decrypted = try? decryptAES(encrypted, key: deriveKey(from: pin, salt: salt)),
              let map = try? JSONSerialization.jsonObject(with: decrypted) as? [String: String] else { return [:] }
        var result = [Int: Data]()
        for (k, v) in map {
            guard let idx = Int(k) else { continue }
            var bytes = [UInt8](); var i = v.startIndex
            while i < v.endIndex {
                let n = v.index(i, offsetBy: 2)
                if let b = UInt8(v[i..<n], radix: 16) { bytes.append(b) }
                i = n
            }
            result[idx] = Data(bytes)
        }
        return result
    }

    // MARK: - Per-site account map (which account each connected origin sees → privacy isolation)

    static func saveSiteAccounts(_ map: [String: Int]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        _ = saveItem(data, account: siteAccountsAccount)
    }

    static func loadSiteAccounts() -> [String: Int] {
        guard let data = loadItem(account: siteAccountsAccount),
              let map = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return map
    }

    // MARK: - API keys (user-entered service secrets — out of plaintext UserDefaults/backups)

    static func saveZeroExKey(_ key: String) { saveString(key, account: zeroExKeyAccount) }
    static func loadZeroExKey() -> String? { loadString(account: zeroExKeyAccount) }
    static func saveBasescanKey(_ key: String) { saveString(key, account: basescanKeyAccount) }
    static func loadBasescanKey() -> String? { loadString(account: basescanKeyAccount) }

    // MARK: - Local activity feed (encrypted at rest in the Keychain, not plaintext UserDefaults)

    static func saveActivity(_ data: Data) { _ = saveItem(data, account: activityAccount) }
    static func loadActivity() -> Data? { loadItem(account: activityAccount) }
    static func deleteActivity() { deleteItem(activityAccount) }

    // MARK: - Portfolio value history (per-account snapshots — wealth/behavior data, device-only)

    static func savePortfolioHistory(_ data: Data) { _ = saveItem(data, account: portfolioHistoryAccount) }
    static func loadPortfolioHistory() -> Data? { loadItem(account: portfolioHistoryAccount) }
    static func deletePortfolioHistory() { deleteItem(portfolioHistoryAccount) }

    private static func saveString(_ value: String, account: String) {
        guard !value.isEmpty, let data = value.data(using: .utf8) else { deleteItem(account); return }
        _ = saveItem(data, account: account)
    }

    private static func loadString(account: String) -> String? {
        guard let data = loadItem(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // Generic string secrets keyed by an arbitrary account (used by WalletConnect for the project
    // id and relay client key). Device-only, out of backups, like everything else here.
    static func saveString(_ value: String, forKey key: String) { saveString(value, account: key) }
    static func loadString(forKey key: String) -> String? { loadString(account: key) }

    // MARK: - Public address (kept in the Keychain so the device↔on-chain-identity link stays
    // out of plaintext UserDefaults and backups; the address itself is public on-chain)

    static func saveAddress(_ address: String) {
        guard let data = address.data(using: .utf8) else { return }
        _ = saveItem(data, account: addressAccount)
    }

    static func loadAddress() -> String? {
        guard let data = loadItem(account: addressAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Connected dApp sites (which sites you use is browsing-habit data → keep it
    // encrypted + device-only + out of backups, not in plaintext UserDefaults)

    static func saveConnectedSites(_ origins: [String]) {
        guard let data = try? JSONEncoder().encode(origins) else { return }
        _ = saveItem(data, account: connectedSitesAccount)
    }

    static func loadConnectedSites() -> [String] {
        guard let data = loadItem(account: connectedSitesAccount),
              let origins = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return origins
    }

    // MARK: - Recovery copy (recovery-code-encrypted)

    /// Stores a second copy of the seed, encrypted with the recovery code. Enables a real
    /// "forgot PIN" reset: decrypt with the code, re-encrypt under a new PIN.
    @discardableResult
    static func saveRecoverySeed(_ words: [String], recoveryCode: String) -> Bool {
        guard let phraseData = words.joined(separator: " ").data(using: .utf8) else { return false }
        let key = deriveKey(from: recoveryCode.uppercased(), salt: loadOrCreateSalt())
        guard let encrypted = try? encryptAES(phraseData, key: key) else { return false }
        return saveItem(encrypted, account: recoverySeedAccount)
    }

    static func loadRecoverySeed(recoveryCode: String) -> [String]? {
        guard let encrypted = loadItem(account: recoverySeedAccount), let salt = loadSalt() else { return nil }
        return decryptSeed(encrypted, secret: recoveryCode.uppercased(), salt: salt)
    }

    // MARK: - Biometric unlock secret

    /// Stores the PIN behind a Secure-Enclave-backed biometric gate (`.biometryCurrentSet`): the
    /// item can ONLY be read after a fresh biometric match, and is invalidated if the device's
    /// biometric enrollment changes. This way, local code (or forensic extraction) can't read the
    /// PIN — and thus can't shortcut the seed — without the user's live Face/Touch ID.
    @discardableResult
    static func saveBiometricPIN(_ pin: String) -> Bool {
        guard let data = pin.data(using: .utf8) else { return false }
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil) else { return false }
        deleteItem(biometricPINAccount)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: biometricPINAccount,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: access,
            kSecAttrSynchronizable as String: false,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Reads the biometric PIN. Pass the LAContext from a just-completed biometric evaluation so the
    /// Keychain reuses that authentication instead of prompting a second time.
    static func loadBiometricPIN(context: LAContext? = nil) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: biometricPINAccount,
            kSecReturnData as String: true,
        ]
        if let context { query[kSecUseAuthenticationContext as String] = context }
        else { query[kSecUseOperationPrompt as String] = "Unlock your Searxly wallet" }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteBiometricPIN() {
        deleteItem(biometricPINAccount)
    }

    // MARK: - Crypto

    private static func decryptSeed(_ encrypted: Data, secret: String, salt: Data) -> [String]? {
        let key = deriveKey(from: secret, salt: salt)
        guard let decrypted = try? decryptAES(encrypted, key: key),
              let phrase = String(data: decrypted, encoding: .utf8) else { return nil }
        let words = phrase.components(separatedBy: " ").filter { !$0.isEmpty }
        return words.isEmpty ? nil : words
    }

    private static func deriveKey(from secret: String, salt: Data) -> Data {
        var derived = [UInt8](repeating: 0, count: 32)
        salt.withUnsafeBytes { saltPtr in
            _ = CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                secret, secret.utf8.count,
                saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                pbkdf2Rounds,
                &derived, 32
            )
        }
        return Data(derived)
    }

    /// Per-wallet random KDF salt. Created once and stored device-only.
    private static func loadOrCreateSalt() -> Data {
        if let existing = loadSalt() { return existing }
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)
        let salt = Data(bytes)
        _ = saveItem(salt, account: saltAccount)
        return salt
    }

    private static func loadSalt() -> Data? { loadItem(account: saltAccount) }

    private static func encryptAES(_ plaintext: Data, key: Data) throws -> Data {
        try AES.GCM.seal(plaintext, using: SymmetricKey(data: key)).combined!
    }

    private static func decryptAES(_ ciphertext: Data, key: Data) throws -> Data {
        try AES.GCM.open(try AES.GCM.SealedBox(combined: ciphertext), using: SymmetricKey(data: key))
    }

    // MARK: - Keychain primitives

    @discardableResult
    private static func saveItem(_ data: Data, account: String) -> Bool {
        deleteItem(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static func loadItem(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func deleteItem(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
