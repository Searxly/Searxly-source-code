//
//  RLP.swift
//  Searxly
//
//  Recursive Length Prefix encoding (Ethereum's serialization format).
//  https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/
//

import Foundation

enum RLP {

    /// An RLP-encodable item: either a byte string or a list of items.
    indirect enum Item {
        case bytes(Data)
        case list([Item])
    }

    // MARK: - Encoding

    static func encode(_ item: Item) -> Data {
        switch item {
        case .bytes(let data):
            return encodeBytes(data)
        case .list(let items):
            var payload = Data()
            for sub in items { payload.append(encode(sub)) }
            return encodeLength(payload.count, offset: 0xc0) + payload
        }
    }

    private static func encodeBytes(_ data: Data) -> Data {
        // Single byte < 0x80 is its own encoding
        if data.count == 1 && data[data.startIndex] < 0x80 {
            return data
        }
        return encodeLength(data.count, offset: 0x80) + data
    }

    private static func encodeLength(_ length: Int, offset: UInt8) -> Data {
        if length < 56 {
            return Data([offset + UInt8(length)])
        }
        let lengthBytes = bigEndianBytes(of: length)
        return Data([offset + 55 + UInt8(lengthBytes.count)]) + lengthBytes
    }

    // MARK: - Helpers

    /// Minimal big-endian byte representation of an integer (no leading zero bytes).
    private static func bigEndianBytes(of value: Int) -> Data {
        var v = value
        var bytes = [UInt8]()
        while v > 0 {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        }
        return Data(bytes)
    }

    // MARK: - Convenience constructors for Ethereum values

    /// Encodes an unsigned integer as a minimal big-endian byte string.
    /// Zero → empty string (RLP convention).
    static func int(_ value: UInt64) -> Item {
        if value == 0 { return .bytes(Data()) }
        var v = value
        var bytes = [UInt8]()
        while v > 0 {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        }
        return .bytes(Data(bytes))
    }

    /// Encodes a big-endian byte array (already minimal) as an integer item.
    /// Strips leading zero bytes per RLP integer convention.
    static func bigInt(_ bytes: [UInt8]) -> Item {
        var trimmed = bytes
        while trimmed.first == 0 { trimmed.removeFirst() }
        return .bytes(Data(trimmed))
    }

    /// Encodes a hex address/data string ("0x…") as a byte string.
    static func hex(_ hexString: String) -> Item {
        .bytes(dataFromHex(hexString))
    }

    static func dataFromHex(_ hexString: String) -> Data {
        var hex = hexString
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        if hex.count % 2 != 0 { hex = "0" + hex }
        var data = Data()
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            if let b = UInt8(hex[idx..<next], radix: 16) { data.append(b) }
            idx = next
        }
        return data
    }
}
