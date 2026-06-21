# Wallet crypto known-answer tests

Standalone, runnable tests for the Searxly wallet's cryptography core.

```sh
cd WalletCryptoTests
swift run            # builds + runs; exits non-zero on any failure
```

## Why this exists

The live "send from an empty wallet → insufficient funds" check passes for *any*
recovered address, so it can't catch a broken hash or a wrong derivation. These tests
assert **exact, independently-known outputs**, so they do:

- **Keccak-256** vs. canonical `keccak("")` / `keccak("abc")` vectors.
- **BIP-39** seed vs. the official Trezor vector, plus checksum validation
  (a typo'd / reordered phrase is rejected).
- **HD derivation** `m/44'/60'/0'/0/i` vs. the standard **Anvil/Foundry** and
  **MetaMask** addresses (`test test … junk`, `abandon … about`).
- **Imported private key** → address (Anvil #0 raw key).
- **personal_sign / EIP-712** signatures recover to the signer; the EIP-712 "Mail"
  digest matches the spec value `be609aee…0957bd2`.
- **EIP-1559** transactions sign, recover the sender, and are **low-S (EIP-2)**.
- **AddressValidator** and **WalletPhishingGuard** fund-safety gates.

## How it stays in sync

`Sources/WalletCryptoTests/crypto/*.swift` are **symlinks** to the real files in
`../Searxly/Wallet/`. The tests always compile and run against production code — they
can never silently drift from what ships.

> Note: this is a SwiftPM package, intentionally separate from the Xcode project so it
> needs no `project.pbxproj` changes. Wiring it as an in-app XCTest target is a possible
> follow-up; this package already proves the crypto compiles and passes in isolation.
