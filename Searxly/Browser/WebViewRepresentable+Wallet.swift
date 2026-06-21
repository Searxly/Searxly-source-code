//
//  WebViewRepresentable+Wallet.swift
//  Searxly
//
//  Bridges the injected EIP-1193 provider (window.ethereum) to WalletProviderBridge.
//  Uses WKScriptMessageHandlerWithReply so the page can await results directly.
//
//  Safety: only main-frame, secure-origin requests are accepted; the origin is taken
//  from WebKit's frame info, never from page-supplied data.
//

import WebKit

extension WebViewRepresentable.Coordinator: WKScriptMessageHandlerWithReply {

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.name == "searxlyWallet" else {
            replyHandler(["error": ["code": -32601, "message": "Unknown handler"]], nil)
            return
        }

        // Reject requests that don't come from the top frame.
        guard message.frameInfo.isMainFrame else {
            replyHandler(["error": ["code": 4100, "message": "Wallet requests from embedded frames are not allowed"]], nil)
            return
        }

        let origin = Self.originString(from: message.frameInfo)
        guard !origin.isEmpty, origin.hasPrefix("https://") || origin.hasPrefix("http://localhost") else {
            replyHandler(["error": ["code": 4100, "message": "Wallet requires a secure (https) site"]], nil)
            return
        }

        guard let body = message.body as? [String: Any], let method = body["method"] as? String else {
            replyHandler(["error": ["code": -32600, "message": "Invalid request"]], nil)
            return
        }
        let params = (body["params"] as? [Any]) ?? []

        Task { @MainActor in
            let reply = await WalletProviderBridge.shared.handle(method: method, params: params, origin: origin)
            replyHandler(reply, nil)
        }
    }

    /// Builds a canonical "scheme://host[:port]" origin from WebKit's frame security origin.
    static func originString(from frame: WKFrameInfo) -> String {
        let o = frame.securityOrigin
        if !o.host.isEmpty {
            let scheme = o.`protocol`.isEmpty ? "https" : o.`protocol`
            let defaultPort = (scheme == "https" && o.port == 443) || (scheme == "http" && o.port == 80)
            let portSuffix = (o.port == 0 || defaultPort) ? "" : ":\(o.port)"
            return "\(scheme)://\(o.host)\(portSuffix)"
        }
        // Fallback to the request URL's origin.
        if let url = frame.request.url, let host = url.host {
            let scheme = url.scheme ?? "https"
            let portSuffix = url.port.map { ":\($0)" } ?? ""
            return "\(scheme)://\(host)\(portSuffix)"
        }
        return ""
    }
}
