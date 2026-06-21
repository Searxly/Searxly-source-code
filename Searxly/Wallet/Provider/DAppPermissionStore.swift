//
//  DAppPermissionStore.swift
//  Searxly
//
//  Per-origin wallet connection permissions. A site only sees the account after the
//  user explicitly connects it; connections are persisted (device-only) and revocable
//  from Settings → Wallet → Connected sites.
//

import Foundation
import Observation

@MainActor
@Observable
final class DAppPermissionStore {
    static let shared = DAppPermissionStore()

    private let legacyKey = "Wallet.connectedOrigins"
    private(set) var connectedOrigins: [String]
    /// Which HD account each connected origin sees. Keeping different sites on different accounts
    /// means they can't be linked to one on-chain identity.
    private(set) var accountByOrigin: [String: Int]

    private init() {
        // Stored encrypted in the Keychain (not plaintext UserDefaults). One-time migration:
        // if an old plaintext list exists, move it into the Keychain and wipe the plaintext copy.
        if let legacy = UserDefaults.standard.stringArray(forKey: legacyKey) {
            connectedOrigins = legacy
            WalletKeychain.saveConnectedSites(legacy)
            UserDefaults.standard.removeObject(forKey: legacyKey)
        } else {
            connectedOrigins = WalletKeychain.loadConnectedSites()
        }
        accountByOrigin = WalletKeychain.loadSiteAccounts()
    }

    func isConnected(_ origin: String) -> Bool {
        connectedOrigins.contains(origin)
    }

    /// The account index a connected origin uses (nil if not connected / not yet mapped).
    func accountIndex(for origin: String) -> Int? {
        accountByOrigin[origin]
    }

    func connect(_ origin: String, accountIndex: Int) {
        guard !origin.isEmpty else { return }
        if !connectedOrigins.contains(origin) { connectedOrigins.append(origin) }
        accountByOrigin[origin] = accountIndex
        persist()
    }

    func disconnect(_ origin: String) {
        connectedOrigins.removeAll { $0 == origin }
        accountByOrigin[origin] = nil
        persist()
    }

    func disconnectAll() {
        connectedOrigins.removeAll()
        accountByOrigin.removeAll()
        persist()
    }

    /// Disconnects any sites that were using a now-removed account.
    func removeMappings(toAccount index: Int) {
        let affected = accountByOrigin.filter { $0.value == index }.map { $0.key }
        guard !affected.isEmpty else { return }
        for origin in affected {
            connectedOrigins.removeAll { $0 == origin }
            accountByOrigin[origin] = nil
        }
        persist()
    }

    private func persist() {
        WalletKeychain.saveConnectedSites(connectedOrigins)
        WalletKeychain.saveSiteAccounts(accountByOrigin)
    }
}
