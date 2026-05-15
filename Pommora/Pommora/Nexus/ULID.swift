//
//  ULID.swift
//  Pommora
//

import Foundation

/// Universally Unique Lexicographically Sortable Identifier.
///
/// 26-character Crockford base32 string: 10 chars timestamp (ms since epoch)
/// + 16 chars cryptographically random. Lexicographically sortable by
/// generation time, more compact than UUID, agent-readable.
///
/// Spec: https://github.com/ulid/spec
enum ULID {
    private static let alphabet: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Generates a new ULID. Pass `at:` only in tests for deterministic timestamps.
    static func generate(at date: Date = .now) -> String {
        encodeTimestamp(UInt64(date.timeIntervalSince1970 * 1000)) + encodeRandom()
    }

    private static func encodeTimestamp(_ timestamp: UInt64) -> String {
        var result = ""
        result.reserveCapacity(10)
        for position in (0..<10).reversed() {
            let index = Int((timestamp >> (position * 5)) & 0x1F)
            result.append(alphabet[index])
        }
        return result
    }

    private static func encodeRandom() -> String {
        let bytes: [UInt8] = (0..<10).map { _ in UInt8.random(in: 0...255) }

        var bits: UInt64 = 0
        var bitCount = 0
        var byteIndex = 0
        var result = ""
        result.reserveCapacity(16)

        while result.count < 16 {
            if bitCount < 5 && byteIndex < bytes.count {
                bits = (bits << 8) | UInt64(bytes[byteIndex])
                bitCount += 8
                byteIndex += 1
                continue
            }
            let shift = bitCount - 5
            result.append(alphabet[Int((bits >> shift) & 0x1F)])
            bitCount -= 5
            bits &= (UInt64(1) << bitCount) &- 1
        }

        return result
    }
}
