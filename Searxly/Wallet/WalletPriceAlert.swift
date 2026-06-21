//
//  WalletPriceAlert.swift
//  Searxly
//
//  User-set price thresholds. When a token's USD price crosses the target, the wallet posts a local
//  notification and the alert is consumed (one-shot, so it never spams). Stored in UserDefaults —
//  it's just a symbol + a number, nothing sensitive, and uses the price feed the wallet already polls.
//

import Foundation

struct WalletPriceAlert: Codable, Identifiable, Equatable {
    var id = UUID()
    let tokenID: String        // matches WalletToken.id
    let tokenSymbol: String
    let targetUSD: Double
    let above: Bool            // notify when price rises to/above (true) or falls to/below (false) target
    var createdAt = Date()

    func crossed(currentUSD: Double) -> Bool {
        guard currentUSD > 0 else { return false }
        return above ? currentUSD >= targetUSD : currentUSD <= targetUSD
    }

    var directionWord: String { above ? "above" : "below" }
}

enum WalletPriceAlertStore {
    static func load() -> [WalletPriceAlert] {
        guard let data = UserDefaults.standard.data(forKey: WalletConfig.Keys.priceAlerts),
              let alerts = try? JSONDecoder().decode([WalletPriceAlert].self, from: data) else { return [] }
        return alerts
    }

    static func save(_ alerts: [WalletPriceAlert]) {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        UserDefaults.standard.set(data, forKey: WalletConfig.Keys.priceAlerts)
    }
}
