//
//  WalletProviderScript.swift
//  Searxly
//
//  The EIP-1193 / EIP-6963 provider injected into every page at document start.
//  It exposes window.ethereum and announces "Searxly Wallet" so dApp "Connect" modals
//  list it exactly like the Phantom/MetaMask browser extensions. All requests are
//  forwarded to Swift (WKScriptMessageHandlerWithReply named "searxlyWallet"), which
//  enforces approval + biometrics. No keys ever live in the page.
//

import Foundation

enum WalletProviderScript {
    /// Builds the injected provider source for the wallet's current chain. The chain id is baked in
    /// at injection so a dApp reading `window.ethereum.chainId` synchronously sees the right network;
    /// later switches arrive via the `chainChanged` event.
    static func source(chainIdHex: String = "0x2105", networkVersion: String = "8453") -> String { """
    (function () {
      if (window.__searxlyWallet) { return; }
      var CHAIN_ID = '\(chainIdHex)';
      var listeners = {};

      function emit(event, data) {
        (listeners[event] || []).slice().forEach(function (fn) { try { fn(data); } catch (e) {} });
      }

      function postToNative(payload) {
        try {
          return window.webkit.messageHandlers.searxlyWallet.postMessage(payload);
        } catch (e) {
          return Promise.reject(e);
        }
      }

      function request(args) {
        var method = args && args.method;
        var params = (args && args.params) || [];
        return postToNative({ method: method, params: params }).then(function (reply) {
          if (reply && reply.error) {
            var err = new Error(reply.error.message || 'Request failed');
            err.code = reply.error.code || -32603;
            throw err;
          }
          var result = reply ? reply.result : null;
          // Keep legacy fields in sync from THIS page's own results (no cross-tab broadcast).
          if ((method === 'eth_requestAccounts' || method === 'eth_accounts') && Array.isArray(result)) {
            provider.selectedAddress = result[0] || null;
          }
          if (method === 'eth_chainId' && typeof result === 'string') { provider.chainId = result; }
          return result;
        });
      }

      var provider = {
        isSearxly: true,
        isMetaMask: false,
        chainId: CHAIN_ID,
        networkVersion: '\(networkVersion)',
        selectedAddress: null,
        request: request,
        on: function (event, handler) { (listeners[event] = listeners[event] || []).push(handler); return provider; },
        addListener: function (event, handler) { return provider.on(event, handler); },
        removeListener: function (event, handler) {
          listeners[event] = (listeners[event] || []).filter(function (h) { return h !== handler; });
          return provider;
        },
        removeAllListeners: function (event) { if (event) { delete listeners[event]; } else { listeners = {}; } return provider; },
        enable: function () { return request({ method: 'eth_requestAccounts' }); },
        isConnected: function () { return true; },
        send: function (m, p) {
          if (typeof m === 'string') { return request({ method: m, params: p || [] }); }
          if (m && typeof m.method === 'string') { return request({ method: m.method, params: m.params || [] }); }
          return Promise.reject(new Error('Unsupported send'));
        },
        sendAsync: function (payload, cb) {
          request({ method: payload.method, params: payload.params || [] })
            .then(function (result) { cb(null, { id: payload.id, jsonrpc: '2.0', result: result }); })
            .catch(function (error) { cb(error, null); });
        }
      };

      window.__searxlyWalletEmit = function (event, dataJson) {
        var data;
        try { data = JSON.parse(dataJson); } catch (e) { data = dataJson; }
        if (event === 'accountsChanged') { provider.selectedAddress = (data && data[0]) || null; }
        if (event === 'chainChanged') { provider.chainId = data; provider.networkVersion = String(parseInt(data, 16)); }
        emit(event, data);
      };

      try {
        window.ethereum = provider;
      } catch (e) {
        Object.defineProperty(window, 'ethereum', { value: provider, configurable: true });
      }
      window.__searxlyWallet = provider;

      // EIP-6963 — makes "Searxly Wallet" selectable in dApp connect modals.
      var SVG = "<svg xmlns='http://www.w3.org/2000/svg' width='96' height='96'>" +
        "<rect width='96' height='96' rx='22' fill='#0a0a0a'/>" +
        "<path d='M70.5 35 L70.5 61 L48 74 L25.5 61 L25.5 35 L48 22 Z' fill='none' stroke='#ffffff' stroke-width='6' stroke-linejoin='round'/>" +
        "<circle cx='48' cy='48' r='7.5' fill='#ffffff'/></svg>";
      var ICON;
      try { ICON = 'data:image/svg+xml;base64,' + btoa(SVG); } catch (e) { ICON = ''; }

      function announce() {
        var uuid = (window.crypto && window.crypto.randomUUID) ? window.crypto.randomUUID()
          : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
              var r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
            });
        var info = { uuid: uuid, name: 'Searxly Wallet', icon: ICON, rdns: 'app.searxly.wallet' };
        try {
          window.dispatchEvent(new CustomEvent('eip6963:announceProvider', {
            detail: Object.freeze({ info: info, provider: provider })
          }));
        } catch (e) {}
      }

      window.addEventListener('eip6963:requestProvider', announce);
      announce();

      try { window.dispatchEvent(new Event('ethereum#initialized')); } catch (e) {}
    })();
    """ }
}
