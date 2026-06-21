//
//  EthereumTransaction.swift
//  Searxly
//
//  EIP-1559 (type 0x02) transaction building, signing (secp256k1 recoverable),
//  and serialization to a raw broadcastable hex string.
//

import Foundation

struct EthereumTransaction {
    var chainId: UInt64
    var nonce: UInt64
    var maxPriorityFeePerGas: UInt64
    var maxFeePerGas: UInt64
    var gasLimit: UInt64
    var to: String            // "0x…" recipient or contract
    var valueWei: [UInt8]     // big-endian, minimal
    var data: Data            // call data (empty for plain ETH transfer)

    // MARK: - Build & sign

    /// Returns the raw signed transaction as a "0x…" hex string ready for eth_sendRawTransaction.
    func signedRawTransaction(privateKey: Data) -> String? {
        // 1. Unsigned payload (9 fields), type-prefixed, hashed
        let unsignedItems: [RLP.Item] = [
            RLP.int(chainId),
            RLP.int(nonce),
            RLP.int(maxPriorityFeePerGas),
            RLP.int(maxFeePerGas),
            RLP.int(gasLimit),
            RLP.hex(to),
            RLP.bigInt(valueWei),
            .bytes(data),
            .list([]),                 // empty access list
        ]
        let unsignedRLP = RLP.encode(.list(unsignedItems))
        var preimage = Data([0x02])    // EIP-1559 transaction type
        preimage.append(unsignedRLP)
        let sighash = Keccak256.hash(preimage)

        // 2. Recoverable ECDSA signature
        guard let sig = EthereumSigner.sign(hash32: sighash, privateKey: privateKey) else { return nil }

        // 3. Signed payload (12 fields): unsigned + yParity, r, s
        let signedItems: [RLP.Item] = unsignedItems + [
            RLP.int(UInt64(sig.recid)),     // yParity (0 or 1)
            RLP.bigInt(sig.r),
            RLP.bigInt(sig.s),
        ]
        let signedRLP = RLP.encode(.list(signedItems))
        var raw = Data([0x02])
        raw.append(signedRLP)

        return "0x" + raw.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - ERC-20 call data

    /// Builds the `transfer(address,uint256)` call data for an ERC-20 token.
    static func erc20TransferData(to recipient: String, amountBytes: [UInt8]) -> Data {
        // selector = keccak256("transfer(address,uint256)")[0:4] = 0xa9059cbb
        encodeAddressUint(selector: [0xa9, 0x05, 0x9c, 0xbb], address: recipient, amountBytes: amountBytes)
    }

    /// Builds the `approve(address,uint256)` call data for an ERC-20 token (used by swaps).
    static func erc20ApproveData(spender: String, amountBytes: [UInt8]) -> Data {
        // selector = keccak256("approve(address,uint256)")[0:4] = 0x095ea7b3
        encodeAddressUint(selector: [0x09, 0x5e, 0xa7, 0xb3], address: spender, amountBytes: amountBytes)
    }

    /// ABI-encodes `selector || address(32) || uint256(32)`.
    private static func encodeAddressUint(selector: [UInt8], address: String, amountBytes: [UInt8]) -> Data {
        var data = Data(selector)
        let addr = RLP.dataFromHex(address)
        data.append(Data(repeating: 0, count: max(0, 32 - addr.count)))
        data.append(addr)
        data.append(Data(repeating: 0, count: max(0, 32 - amountBytes.count)))
        data.append(contentsOf: amountBytes)
        return data
    }
}
