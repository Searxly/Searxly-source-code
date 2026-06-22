//
//  SearxlyGateway.swift
//  Searxly
//
//  Single source of truth for the Searxly gateway — the tiny server that fronts every third-party
//  service Searxly needs a secret key for (io.net for Searxly AI, 0x for swaps, Etherscan for wallet
//  history). The app NEVER holds those upstream keys; it only sends the gateway's app token, and the
//  gateway attaches the real key server-side. See gateway/ in the repo for the server.
//
//  END USERS NEVER SEE THESE VALUES. The app token is a soft gate (it ships in the app, so its only
//  jobs are to stop casual abuse and to be rotatable server-side without an app update).
//
//  baseURL currently uses a free nip.io hostname (no DNS setup needed) for bring-up. For launch,
//  switch `host` to a real subdomain (e.g. https://gateway.searxly.app) — change the Caddyfile + here.
//

import Foundation

enum SearxlyGateway {
    /// Scheme + host of the gateway (no trailing slash, no path).
    nonisolated static let host = "https://gateway.searxly.app"

    /// The gateway's app token, sent as `Authorization: Bearer <appToken>` on every route. This is a
    /// SOFT gate, never an upstream secret — the gateway holds the real io.net / 0x keys server-side,
    /// so a leaked token only enables (rate-limited) use of the proxy, never access to those keys.
    ///
    /// Resolution order, so the token can be rotated and kept OUT of the public source tree without a
    /// code change: (1) the `SEARXLY_GATEWAY_APP_TOKEN` environment variable, (2) the
    /// `SearxlyGatewayAppToken` Info.plist key (wire it to a gitignored xcconfig for release builds),
    /// (3) the compiled-in fallback below.
    nonisolated static let appToken: String = {
        if let env = ProcessInfo.processInfo.environment["SEARXLY_GATEWAY_APP_TOKEN"], !env.isEmpty {
            return env
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "SearxlyGatewayAppToken") as? String,
           !plist.isEmpty {
            return plist
        }
        return fallbackAppToken
    }()

    /// Compiled-in fallback token. INTENTIONALLY BLANK in the public source — the real token is
    /// supplied per-build via the `SEARXLY_GATEWAY_APP_TOKEN` env var (Xcode scheme) or the
    /// `SearxlyGatewayAppToken` Info.plist key (wire to a gitignored xcconfig). It is only a soft gate;
    /// the real upstream keys live server-side in the gateway, never in the app.
    private nonisolated static let fallbackAppToken = ""

    /// True once the gateway is wired up, so callers can fall back gracefully when it isn't.
    nonisolated static var isConfigured: Bool { !appToken.isEmpty }

    // MARK: - Route bases

    /// OpenAI-compatible AI endpoint base (the provider appends `chat/completions`).
    nonisolated static var aiBaseURL: URL { URL(string: "\(host)/v1")! }

    /// 0x swap proxy base. Callers append the upstream path (e.g. `/swap/allowance-holder/quote`).
    nonisolated static var zeroExBase: String { "\(host)/wallet/0x" }

    /// Etherscan v2 proxy endpoint. Callers pass the usual query items WITHOUT `apikey`.
    nonisolated static var etherscanBase: String { "\(host)/wallet/etherscan" }

    /// Convenience `Authorization` header value for the proxied wallet routes.
    nonisolated static var bearer: String { "Bearer \(appToken)" }
}
