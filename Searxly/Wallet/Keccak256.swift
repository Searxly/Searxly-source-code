//
//  Keccak256.swift
//  Searxly
//
//  Pure Swift implementation of Keccak-256 (Ethereum's hash function).
//  Note: This is Keccak, NOT SHA-3 (NIST padded differently).
//

import Foundation

enum Keccak256 {
    static func hash(_ data: Data) -> Data {
        var state = [UInt64](repeating: 0, count: 25)
        let rate = 136  // 1088 bits / 8 = 136 bytes (Keccak-256 rate)

        var buf = Array(data)
        // Padding: Keccak uses 0x01 ... 0x80
        buf.append(0x01)
        while buf.count % rate != 0 { buf.append(0x00) }
        buf[buf.count - 1] |= 0x80

        // Absorb
        var offset = 0
        while offset < buf.count {
            for i in 0..<(rate / 8) {
                var lane: UInt64 = 0
                for b in 0..<8 { lane |= UInt64(buf[offset + i*8 + b]) << (b*8) }
                state[i] ^= lane
            }
            keccakF1600(&state)
            offset += rate
        }

        // Squeeze 32 bytes
        var digest = Data(count: 32)
        for i in 0..<4 {
            let lane = state[i]
            for b in 0..<8 { digest[i*8 + b] = UInt8((lane >> (b*8)) & 0xFF) }
        }
        return digest
    }

    // MARK: - Keccak-f[1600]

    private static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
        0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
        0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]

    private static let rotationOffsets: [Int] = [
         0,  1, 62, 28, 27, 36, 44,  6, 55, 20,
         3, 10, 43, 25, 39, 41, 45, 15, 21,  8,
        18,  2, 61, 56, 14,
    ]

    private static func keccakF1600(_ state: inout [UInt64]) {
        for round in 0..<24 {
            // θ
            var C = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 { C[x] = state[x] ^ state[x+5] ^ state[x+10] ^ state[x+15] ^ state[x+20] }
            var D = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 { D[x] = C[(x+4)%5] ^ rotl(C[(x+1)%5], 1) }
            for i in 0..<25 { state[i] ^= D[i%5] }

            // ρ and π — B[y][(2x+3y) mod 5] = ROT(A[x][y], r[x][y]); lane flat index = col + 5*row
            var B = [UInt64](repeating: 0, count: 25)
            for x in 0..<5 {
                for y in 0..<5 {
                    B[y + 5*((2*x + 3*y) % 5)] = rotl(state[x + 5*y], rotationOffsets[x + 5*y])
                }
            }

            // χ
            for x in 0..<5 {
                for y in 0..<5 {
                    state[x+y*5] = B[x+y*5] ^ ((~B[(x+1)%5+y*5]) & B[(x+2)%5+y*5])
                }
            }

            // ι
            state[0] ^= roundConstants[round]
        }
    }

    @inline(__always)
    private static func rotl(_ x: UInt64, _ n: Int) -> UInt64 {
        (x << n) | (x >> (64 - n))
    }
}
