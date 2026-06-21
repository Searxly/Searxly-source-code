//
//  PasswordVaultManager.swift
//  Searxly
//
//  On-device password vault coordinator: preferences, metadata, secrets, and browser fill helpers.
//  Secrets live in Keychain (PasswordVaultSecureStore); metadata in AppData.
//

import Foundation
import LocalAuthentication
import Security

@MainActor
@Observable
final class PasswordVaultManager {
    static let shared = PasswordVaultManager()

    private(set) var savedLoginCount: Int = 0
    private(set) var entries: [PasswordVaultEntry] = []
    private(set) var isVaultUnlocked: Bool = false

    var useCustomVaultPassphrase: Bool {
        VaultLockManager.shared.useCustomPassphrase
    }

    var autofillEnabled: Bool = true {
        didSet { persistBehaviorPreferences() }
    }

    var offerToSaveEnabled: Bool = true {
        didSet { persistBehaviorPreferences() }
    }

    var suggestPasswordsEnabled: Bool = true {
        didSet { persistBehaviorPreferences() }
    }

    var copyGeneratedToClipboard: Bool = true {
        didSet { persistBehaviorPreferences() }
    }

    var autoLockMinutes: Int = 10 {
        didSet {
            guard !isLoadingPreferences else { return }
            let clamped = max(0, min(autoLockMinutes, 1440))
            if clamped != autoLockMinutes {
                autoLockMinutes = clamped
                return
            }
            Persistence.savePasswordVaultAutoLockMinutes(clamped)
            restartAutoLockTimer()
        }
    }

    private var isLoadingPreferences = false
    private var lastVaultActivity = Date()
    private var autoLockTimer: Timer?
    private var authInProgress = false

    private init() {
        reloadFromPersistence()
    }

    // MARK: - Persistence

    func reloadFromPersistence() {
        isLoadingPreferences = true
        defer { isLoadingPreferences = false }

        VaultLockManager.shared.reloadFromPersistence()

        entries = Persistence.loadPasswordVaultEntries()
            .sorted { lhs, rhs in
                if lhs.domain != rhs.domain { return lhs.domain.localizedCaseInsensitiveCompare(rhs.domain) == .orderedAscending }
                return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
            }
        savedLoginCount = entries.count

        let behavior = Persistence.loadPasswordVaultBehaviorPreferences()
        autofillEnabled = behavior.autofillEnabled
        offerToSaveEnabled = behavior.offerToSaveEnabled
        suggestPasswordsEnabled = behavior.suggestPasswordsEnabled
        copyGeneratedToClipboard = behavior.copyGeneratedToClipboard
        autoLockMinutes = Persistence.loadPasswordVaultAutoLockMinutes()
    }

    private func persistEntries() {
        Persistence.savePasswordVaultEntries(entries)
        savedLoginCount = entries.count
    }

    private func persistBehaviorPreferences() {
        guard !isLoadingPreferences else { return }
        Persistence.savePasswordVaultBehaviorPreferences(
            autofillEnabled: autofillEnabled,
            offerToSaveEnabled: offerToSaveEnabled,
            suggestPasswordsEnabled: suggestPasswordsEnabled,
            copyGeneratedToClipboard: copyGeneratedToClipboard
        )
    }

    // MARK: - Vault lock

    func unlockVault(passphrase: String? = nil) async -> Bool {
        guard !authInProgress else { return false }
        authInProgress = true
        defer { authInProgress = false }

        let success: Bool
        if VaultLockManager.shared.useCustomPassphrase {
            guard let passphrase, VaultLockManager.shared.verifyPassphrase(passphrase) else {
                return false
            }
            success = true
        } else {
            success = await authenticate(reason: "Unlock your password vault")
        }

        if success {
            isVaultUnlocked = true
            recordVaultActivity()
            restartAutoLockTimer()
        }
        return success
    }

    func lockVault() {
        isVaultUnlocked = false
        stopAutoLockTimer()
        VaultClipboardManager.shared.clearIfStillOurs()
    }

    func recordVaultActivity() {
        lastVaultActivity = Date()
    }

    private var activeVaultAuthContext: LAContext?

    private func authenticate(reason: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let context = LAContext()
            activeVaultAuthContext = context
            context.localizedCancelTitle = "Cancel"
            context.localizedFallbackTitle = "Use Password"

            var evalError: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evalError) else {
                activeVaultAuthContext = nil
                #if DEBUG
                print("[Passwords] Biometric auth unavailable: \(evalError?.localizedDescription ?? "unknown")")
                #endif
                continuation.resume(returning: false)
                return
            }

            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, _ in
                Task { @MainActor [weak self] in
                    self?.activeVaultAuthContext = nil
                    continuation.resume(returning: success)
                }
            }
        }
    }

    private func restartAutoLockTimer() {
        stopAutoLockTimer()
        guard isVaultUnlocked, autoLockMinutes > 0 else { return }

        autoLockTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAutoLock()
            }
        }
    }

    private func stopAutoLockTimer() {
        autoLockTimer?.invalidate()
        autoLockTimer = nil
    }

    private func checkAutoLock() {
        guard isVaultUnlocked, autoLockMinutes > 0 else { return }
        let elapsed = Date().timeIntervalSince(lastVaultActivity)
        if elapsed >= TimeInterval(autoLockMinutes * 60) {
            lockVault()
        }
    }

    // MARK: - CRUD

    static func normalizeDomain(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            if let host = URL(string: value)?.host {
                value = host
            }
        }
        if value.hasPrefix("www.") {
            value = String(value.dropFirst(4))
        }
        return value
    }

    func entries(matching query: String) -> [PasswordVaultEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.domain.lowercased().contains(q)
                || $0.username.lowercased().contains(q)
                || ($0.notes?.lowercased().contains(q) ?? false)
        }
    }

    func entries(forDomain domain: String) -> [PasswordVaultEntry] {
        let normalized = Self.normalizeDomain(domain)
        return entries.filter { entry in
            // Exact match, or the stored domain is a registrable parent of the current host
            // e.g. saved "github.com" should match "login.github.com"
            entry.domain == normalized || normalized.hasSuffix(".\(entry.domain)")
        }
    }

    @discardableResult
    func addEntry(domain: String, username: String, password: String, notes: String? = nil) -> PasswordVaultEntry? {
        let normalizedDomain = Self.normalizeDomain(domain)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDomain.isEmpty, !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else { return nil }

        let entry = PasswordVaultEntry(
            domain: normalizedDomain,
            username: trimmedUsername,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )

        guard PasswordVaultSecureStore.savePassword(trimmedPassword, for: entry.id) else { return nil }

        entries.append(entry)
        entries.sort { lhs, rhs in
            if lhs.domain != rhs.domain { return lhs.domain.localizedCaseInsensitiveCompare(rhs.domain) == .orderedAscending }
            return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
        }
        persistEntries()
        recordVaultActivity()
        return entry
    }

    @discardableResult
    func updateEntry(
        id: UUID,
        domain: String,
        username: String,
        password: String?,
        notes: String?
    ) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }

        let normalizedDomain = Self.normalizeDomain(domain)
        guard !normalizedDomain.isEmpty, !username.isEmpty else { return false }

        if let password, !password.isEmpty {
            guard PasswordVaultSecureStore.savePassword(password, for: id) else { return false }
        }

        entries[index].domain = normalizedDomain
        entries[index].username = username
        entries[index].notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        entries.sort { lhs, rhs in
            if lhs.domain != rhs.domain { return lhs.domain.localizedCaseInsensitiveCompare(rhs.domain) == .orderedAscending }
            return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
        }
        persistEntries()
        recordVaultActivity()
        return true
    }

    func deleteEntry(id: UUID) {
        PasswordVaultSecureStore.deletePassword(for: id)
        entries.removeAll { $0.id == id }
        persistEntries()
        recordVaultActivity()
    }

    func password(for entryID: UUID) -> String? {
        guard isVaultUnlocked else { return nil }
        recordVaultActivity()
        return PasswordVaultSecureStore.loadPassword(for: entryID)
    }

    func markEntryUsed(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].lastUsed = Date()
        persistEntries()
    }

    func clearAllVaultData() {
        PasswordVaultSecureStore.deleteAllPasswords()
        entries = []
        persistEntries()
        lockVault()
        #if DEBUG
        print("[Passwords] Cleared vault metadata and Keychain secrets.")
        #endif
    }

    func suggestPasswordWithAI(for domain: String) async -> String {
        _ = domain
        return Self.generateSecurePassword(length: 20)
    }

    static func generateSecurePassword(length: Int = 20) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*")
        guard !chars.isEmpty, length > 0 else { return "" }

        // Rejection-sampling eliminates modulo bias (256 % 70 = 46 → indices 0-45 would be
        // slightly over-represented without this). Accept only bytes in [0, acceptCeiling).
        let acceptCeiling = UInt8((256 / chars.count) * chars.count)
        var password = ""
        password.reserveCapacity(length)

        while password.count < length {
            var randomByte: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &randomByte) == errSecSuccess else { continue }
            if randomByte >= acceptCeiling { continue }
            password.append(chars[Int(randomByte) % chars.count])
        }

        return password
    }

    func copyPasswordToClipboard(for entryID: UUID) -> Bool {
        guard let password = password(for: entryID) else { return false }
        VaultClipboardManager.shared.copySensitive(password)
        markEntryUsed(id: entryID)
        return true
    }

    func copyGeneratedPasswordToClipboard(_ password: String) {
        VaultClipboardManager.shared.copySensitive(password)
    }
}

@MainActor
@Observable
final class VaultLockManager {
    static let shared = VaultLockManager()

    private(set) var useCustomPassphrase: Bool = false

    private let minimumPassphraseLength = 8

    private init() {
        reloadFromPersistence()
    }

    func reloadFromPersistence() {
        let config = Persistence.loadPasswordVaultLockConfig()
        useCustomPassphrase = config.useCustom
            && config.salt != nil
            && config.verifier != nil
    }

    @discardableResult
    func setCustomPassphrase(_ passphrase: String) -> Bool {
        guard passphrase.count >= minimumPassphraseLength,
              let salt = VaultPassphraseCrypto.generateSalt(),
              let verifier = VaultPassphraseCrypto.deriveVerifier(passphrase: passphrase, salt: salt) else {
            return false
        }

        Persistence.savePasswordVaultLockConfig(useCustom: true, salt: salt, verifier: verifier)
        useCustomPassphrase = true
        PasswordVaultManager.shared.lockVault()
        return true
    }

    func verifyPassphrase(_ passphrase: String) -> Bool {
        let config = Persistence.loadPasswordVaultLockConfig()
        guard let salt = config.salt, let verifier = config.verifier else { return false }
        return VaultPassphraseCrypto.verify(passphrase: passphrase, salt: salt, verifier: verifier)
    }

    @discardableResult
    func changePassphrase(from current: String, to newPassphrase: String) -> Bool {
        guard verifyPassphrase(current), newPassphrase.count >= minimumPassphraseLength else { return false }
        return setCustomPassphrase(newPassphrase)
    }

    @discardableResult
    func removeCustomPassphrase(verifying passphrase: String) -> Bool {
        guard verifyPassphrase(passphrase) else { return false }
        clearAllVaultLockData()
        return true
    }

    func clearAllVaultLockData() {
        Persistence.savePasswordVaultLockConfig(useCustom: false, salt: nil, verifier: nil)
        useCustomPassphrase = false
        PasswordVaultManager.shared.lockVault()
        #if DEBUG
        print("[Passwords] Cleared vault lock configuration.")
        #endif
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}