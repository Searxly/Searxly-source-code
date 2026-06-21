//
//  WalletPortfolioHistory.swift
//  Searxly
//
//  Portfolio-value-over-time, built entirely from ON-DEVICE snapshots — no network, nothing fetched.
//  A snapshot of the account's total USD value is appended after each balance refresh. Stored per HD
//  account, encrypted in the Keychain (device-only). Values are kept in USD and converted to the
//  display currency at render time, so switching fiat never corrupts the history.
//

import Foundation
import Observation

struct PortfolioSnapshot: Codable, Equatable {
    let t: Date
    let usd: Double
}

@MainActor
@Observable
final class WalletPortfolioHistoryStore {
    static let shared = WalletPortfolioHistoryStore()

    /// account index → snapshots, oldest first.
    private(set) var byAccount: [Int: [PortfolioSnapshot]] = [:]

    private let minInterval: TimeInterval = 600   // ≥10 min between stored points
    private let maxPoints = 500                    // bound the on-disk series

    private init() { load() }

    /// The snapshot series for an account, oldest-first.
    func series(forAccount index: Int) -> [PortfolioSnapshot] { byAccount[index] ?? [] }

    /// Appends a snapshot for an account. Throttled so rapid refreshes don't spam the series, but a
    /// meaningful value move still records inside the window so real dips/spikes aren't smoothed away.
    func record(accountIndex: Int, usd: Double) {
        guard usd >= 0 else { return }
        var series = byAccount[accountIndex] ?? []
        if let last = series.last {
            let elapsed = Date().timeIntervalSince(last.t)
            let changed = abs(usd - last.usd) > max(0.01, last.usd * 0.005)   // >0.5% (or >1¢) move
            if elapsed < minInterval && !changed { return }
        }
        series.append(PortfolioSnapshot(t: Date(), usd: usd))
        if series.count > maxPoints { series.removeFirst(series.count - maxPoints) }
        byAccount[accountIndex] = series
        persist()
    }

    /// Drops a removed account's series.
    func clear(account index: Int) {
        guard byAccount[index] != nil else { return }
        byAccount[index] = nil
        persist()
    }

    func clearAll() {
        byAccount.removeAll()
        WalletKeychain.deletePortfolioHistory()
    }

    // MARK: - Persistence (string-keyed JSON for deterministic encoding of the Int-keyed map)

    private func persist() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: byAccount.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            WalletKeychain.savePortfolioHistory(data)   // encrypted, device-only, out of backups
        }
    }

    private func load() {
        guard let data = WalletKeychain.loadPortfolioHistory(),
              let decoded = try? JSONDecoder().decode([String: [PortfolioSnapshot]].self, from: data) else { return }
        byAccount = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
    }
}
