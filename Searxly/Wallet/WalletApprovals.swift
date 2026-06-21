//
//  WalletApprovals.swift
//  Searxly
//
//  Token-approval ("allowance") discovery. A stale `approve` — especially an unlimited one — is
//  the #1 way funds get drained long after you stopped using a site, so we surface every active
//  allowance the wallet has granted and let the user revoke it (set it back to 0).
//
//  Discovery is scoped to the tokens the wallet knows about (built-in + custom + auto-discovered)
//  so the eth_getLogs query stays bounded and indexed — public RPCs reject unbounded scans.
//

import Foundation

struct TokenApproval: Identifiable, Equatable {
    let token: WalletToken
    let spender: String
    let allowanceRaw: [UInt8]      // minimal big-endian

    var id: String { token.id + "-" + spender }

    /// Allowances this large are effectively infinite (max-uint / Permit2-style) — treat as unlimited.
    var isUnlimited: Bool { allowanceRaw.count >= 24 }

    private var amount: Double {
        var v = 0.0
        for b in allowanceRaw { v = v * 256 + Double(b) }
        return v / pow(10.0, Double(token.decimals))
    }

    var allowanceDisplay: String {
        if isUnlimited { return "Unlimited" }
        let a = amount
        if a == 0 { return "0" }
        if a < 0.0001 { return String(format: "%.8f", a) }
        return String(format: "%.4f", a)
    }
}

enum WalletApprovals {
    enum LoadState: Equatable {
        case loading
        case loaded([TokenApproval])
        case unsupported   // the RPC couldn't run the allowance scan
    }

    /// Finds active (non-zero) allowances the `owner` has granted across its known `tokens`.
    static func fetch(tokens: [WalletToken], owner: String, rpc: String) async -> LoadState {
        let contracts = tokens.compactMap { $0.contractAddress?.lowercased() }
        guard !contracts.isEmpty else { return .loaded([]) }

        // Primary: RPC eth_getLogs (zero third-party, needs a getLogs-capable RPC). Public RPCs
        // cap log ranges, so fall back to the Basescan logs API when a key is configured.
        var pairs = await WalletNetwork.approvalSpenders(owner: owner, tokenContracts: contracts, rpc: rpc)
        if pairs == nil {
            pairs = await WalletNetwork.approvalSpendersViaExplorer(owner: owner, tokenContracts: contracts)
        }
        guard let pairs else { return .unsupported }

        var result: [TokenApproval] = []
        for (tokenAddr, spender) in pairs {
            guard let token = tokens.first(where: { $0.contractAddress?.lowercased() == tokenAddr }),
                  let raw = await WalletNetwork.allowance(token: tokenAddr, owner: owner, spender: spender, rpc: rpc)
            else { continue }
            if raw == [0] || raw.isEmpty { continue }   // already revoked / never active
            result.append(TokenApproval(token: token, spender: spender, allowanceRaw: raw))
        }
        // Unlimited approvals are the riskiest — show them first.
        return .loaded(result.sorted { $0.isUnlimited && !$1.isUnlimited })
    }
}
