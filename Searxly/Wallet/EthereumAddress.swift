//
//  EthereumAddress.swift
//  Searxly
//
//  BIP-32 HD key derivation + secp256k1 public key + Keccak-256 → Ethereum address.
//  Path: m/44'/60'/0'/0/0  (BIP-44, Ethereum, account 0, external chain, index 0)
//

import Foundation
import CryptoKit
import CommonCrypto
import P256K
import libsecp256k1

enum EthereumAddress {

    // MARK: - Public API

    static func derive(fromSeed seed: Data, index: Int = 0) -> String? {
        guard let priv = derivePrivateKey(fromSeed: seed, index: index) else { return nil }
        return ethereumAddress(privateKey: priv)
    }

    /// Derives the 32-byte secp256k1 private key at m/44'/60'/0'/0/`index` from a BIP-39 seed.
    /// `index` is the BIP-44 address index — each account in the wallet uses a different one.
    static func derivePrivateKey(fromSeed seed: Data, index: Int = 0) -> Data? {
        guard let masterKey = bip32Master(seed: seed) else { return nil }

        // m / 44' / 60' / 0' / 0 / index
        let path: [(UInt32, Bool)] = [
            (44, true),               // purpose (hardened)
            (60, true),               // coin type: ETH (hardened)
            (0,  true),               // account 0 (hardened)
            (0,  false),              // external chain
            (UInt32(max(0, index)), false), // address index
        ]

        var current = masterKey
        for (index, hardened) in path {
            guard let child = bip32Child(parent: current, index: index, hardened: hardened) else { return nil }
            current = child
        }
        return current.key
    }

    /// Public helper: Ethereum address from a raw 32-byte private key.
    static func address(fromPrivateKey privateKey: Data) -> String? {
        ethereumAddress(privateKey: privateKey)
    }

    // MARK: - BIP-32

    private struct ExtendedKey {
        let key: Data        // 32-byte private key
        let chainCode: Data  // 32-byte chain code
    }

    private static func bip32Master(seed: Data) -> ExtendedKey? {
        let keyData = Data("Bitcoin seed".utf8)
        guard let mac = hmacSHA512(key: keyData, data: seed) else { return nil }
        return ExtendedKey(key: mac.prefix(32), chainCode: mac.suffix(32))
    }

    private static func bip32Child(parent: ExtendedKey, index: UInt32, hardened: Bool) -> ExtendedKey? {
        var data = Data()
        let i = hardened ? (0x80000000 | index) : index

        if hardened {
            data.append(0x00)
            data.append(contentsOf: parent.key)
        } else {
            guard let pubKey = compressedPublicKey(privateKey: parent.key) else { return nil }
            data.append(contentsOf: pubKey)
        }
        data.append(UInt8((i >> 24) & 0xFF))
        data.append(UInt8((i >> 16) & 0xFF))
        data.append(UInt8((i >> 8)  & 0xFF))
        data.append(UInt8(i         & 0xFF))

        guard let mac = hmacSHA512(key: parent.chainCode, data: data) else { return nil }
        let il = [UInt8](mac.prefix(32))           // IL
        let childChain = mac.suffix(32)            // IR

        // BIP-32: ki = (IL + kpar) mod n. Use libsecp256k1's tweak-add, which performs the
        // modular addition over the curve order and rejects invalid results.
        guard let ctx = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN)) else { return nil }
        defer { secp256k1_context_destroy(ctx) }

        var childKey = [UInt8](parent.key)         // kpar (tweaked in place)
        let ok = il.withUnsafeBufferPointer { tweakPtr -> Int32 in
            guard let base = tweakPtr.baseAddress else { return 0 }
            return secp256k1_ec_seckey_tweak_add(ctx, &childKey, base)
        }
        guard ok == 1 else { return nil }          // invalid child → caller would advance index (astronomically rare)

        return ExtendedKey(key: Data(childKey), chainCode: childChain)
    }

    // MARK: - secp256k1 helpers via P256K

    private static func compressedPublicKey(privateKey: Data) -> Data? {
        guard let key = try? P256K.Signing.PrivateKey(dataRepresentation: privateKey, format: .compressed) else { return nil }
        return key.publicKey.dataRepresentation  // 33 bytes: 02/03 || x
    }

    private static func uncompressedPublicKey(privateKey: Data) -> Data? {
        guard let key = try? P256K.Signing.PrivateKey(dataRepresentation: privateKey, format: .uncompressed) else { return nil }
        return key.publicKey.dataRepresentation  // 65 bytes: 04 || x || y
    }

    // MARK: - Ethereum address

    private static func ethereumAddress(privateKey: Data) -> String? {
        guard let pubKey = uncompressedPublicKey(privateKey: privateKey) else { return nil }
        // pubKey = 04 || x(32) || y(32); drop the 04 prefix
        let xy = pubKey.dropFirst()
        let hash = Keccak256.hash(xy)
        let addressBytes = hash.suffix(20)
        let hex = addressBytes.map { String(format: "%02x", $0) }.joined()
        return "0x" + checksumAddress(hex)
    }

    // EIP-55 checksum
    private static func checksumAddress(_ hex: String) -> String {
        let lower = hex.lowercased()
        let hashHex = Keccak256.hash(Data(lower.utf8)).map { String(format: "%02x", $0) }.joined()
        return zip(lower, hashHex).map { (ch, hch) -> String in
            guard let h = Int(String(hch), radix: 16), ch.isLetter else { return String(ch) }
            return h >= 8 ? String(ch).uppercased() : String(ch)
        }.joined()
    }

    // MARK: - HMAC-SHA512 (CommonCrypto)

    private static func hmacSHA512(key: Data, data: Data) -> Data? {
        var result = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        key.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { dataBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA512),
                       keyBytes.baseAddress, key.count,
                       dataBytes.baseAddress, data.count,
                       &result)
            }
        }
        return Data(result)
    }
}
