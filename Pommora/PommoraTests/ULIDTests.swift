//
//  ULIDTests.swift
//  PommoraTests
//

import Foundation
import Testing

@testable import Pommora

struct ULIDTests {
    private static let crockfordAlphabet: Set<Character> =
        Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    @Test func generateProduces26Characters() {
        let ulid = ULID.generate()
        #expect(ulid.count == 26)
    }

    @Test func everyCharacterIsCrockfordBase32() {
        let ulid = ULID.generate()
        for char in ulid {
            #expect(Self.crockfordAlphabet.contains(char), "unexpected char \(char) in \(ulid)")
        }
    }

    @Test func generatedIDsAreUniqueAcrossTightLoop() {
        var seen = Set<String>()
        for _ in 0..<10_000 {
            let id = ULID.generate()
            #expect(!seen.contains(id), "duplicate ULID generated: \(id)")
            seen.insert(id)
        }
    }

    @Test func earlierTimestampSortsBeforeLater() {
        let early = ULID.generate(at: Date(timeIntervalSince1970: 1_000))
        let late = ULID.generate(at: Date(timeIntervalSince1970: 2_000))
        #expect(early < late)
    }

    @Test func sameMillisecondTimestampShareTimestampPrefix() {
        let date = Date(timeIntervalSince1970: 1_700_000_000.123)
        let a = ULID.generate(at: date)
        let b = ULID.generate(at: date)
        #expect(a.prefix(10) == b.prefix(10))
    }
}
