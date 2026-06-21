//
//  GasOptions.swift
//  Searxly
//
//  Computes Slow / Normal / Fast EIP-1559 fee tiers from the current base fee and a
//  suggested priority tip. Base L2 fees are tiny, so these are mostly UX comfort tiers.
//

import Foundation

enum GasSpeed: String, CaseIterable, Identifiable {
    case slow, normal, fast
    var id: String { rawValue }
    var label: String {
        switch self {
        case .slow:   return "Slow"
        case .normal: return "Normal"
        case .fast:   return "Fast"
        }
    }
    var symbol: String {
        switch self {
        case .slow:   return "tortoise.fill"
        case .normal: return "gauge.medium"
        case .fast:   return "hare.fill"
        }
    }
}

struct GasFee: Equatable {
    let maxPriorityFeePerGas: UInt64   // wei
    let maxFeePerGas: UInt64           // wei

    /// Worst-case fee in wei for a given gas limit.
    func maxCostWei(gasLimit: UInt64) -> UInt64 { maxFeePerGas &* gasLimit }
}

enum GasOptions {
    /// Sensible fallbacks if the node doesn't return values (Base, sub-gwei).
    static let fallbackTip: UInt64 = 1_000_000        // 0.001 gwei
    static let fallbackBaseFee: UInt64 = 100_000_000  // 0.1 gwei

    /// Builds the three fee tiers. `baseFee` and `priorityTip` are wei.
    static func tiers(baseFee: UInt64, priorityTip: UInt64) -> [GasSpeed: GasFee] {
        let base = baseFee == 0 ? fallbackBaseFee : baseFee
        let tip = priorityTip == 0 ? fallbackTip : priorityTip

        func fee(baseMultTenths: UInt64, tipMultTenths: UInt64) -> GasFee {
            let t = max(tip &* tipMultTenths / 10, 1)
            let maxFee = base &* baseMultTenths / 10 &+ t
            return GasFee(maxPriorityFeePerGas: t, maxFeePerGas: maxFee)
        }

        return [
            .slow:   fee(baseMultTenths: 15, tipMultTenths: 8),    // 1.5× base, 0.8× tip
            .normal: fee(baseMultTenths: 20, tipMultTenths: 10),   // 2.0× base, 1.0× tip
            .fast:   fee(baseMultTenths: 25, tipMultTenths: 15),   // 2.5× base, 1.5× tip
        ]
    }

    static func fee(for speed: GasSpeed, baseFee: UInt64, priorityTip: UInt64) -> GasFee {
        tiers(baseFee: baseFee, priorityTip: priorityTip)[speed]
            ?? GasFee(maxPriorityFeePerGas: fallbackTip, maxFeePerGas: fallbackBaseFee * 2 + fallbackTip)
    }
}
