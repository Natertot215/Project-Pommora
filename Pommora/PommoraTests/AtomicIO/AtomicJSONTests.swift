import Foundation
import Testing
@testable import Pommora

@Suite("AtomicJSON")
struct AtomicJSONTests {

    private struct Sample: Codable, Equatable {
        var name: String
        var count: Int
        var when: Date
    }

    @Test("encode produces pretty-printed, sorted-keys JSON")
    func encodeIsDeterministic() throws {
        let sample = Sample(name: "x", count: 7, when: Date(timeIntervalSince1970: 0))
        let a = try AtomicJSON.encode(sample)
        let b = try AtomicJSON.encode(sample)
        #expect(a == b, "same input must produce byte-identical output")
        let text = String(data: a, encoding: .utf8)!
        // Sorted keys → "count" comes before "name" alphabetically
        let countIndex = text.range(of: "\"count\"")!.lowerBound
        let nameIndex = text.range(of: "\"name\"")!.lowerBound
        #expect(countIndex < nameIndex, "keys must be sorted alphabetically")
        // Pretty-printed → contains newlines + 2-space indent
        #expect(text.contains("\n"), "must be pretty-printed")
        // ISO-8601 dates
        #expect(text.contains("1970-01-01"), "dates must be ISO-8601")
    }

    @Test("write + decode round-trip")
    func roundTrip() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let url = nexus.rootURL.appendingPathComponent("sample.json")
        let original = Sample(name: "Productivity", count: 42, when: Date(timeIntervalSince1970: 1716480000))

        try AtomicJSON.write(original, to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let loaded = try AtomicJSON.decode(Sample.self, from: url)
        #expect(loaded == original)
    }

    @Test("write is atomic — failed write does not corrupt existing file")
    func atomicWriteSafety() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let url = nexus.rootURL.appendingPathComponent("sample.json")
        let first = Sample(name: "a", count: 1, when: Date(timeIntervalSince1970: 0))
        try AtomicJSON.write(first, to: url)

        // Read existing data; ensure write replaced it cleanly
        let loaded = try AtomicJSON.decode(Sample.self, from: url)
        #expect(loaded == first)

        // Overwrite
        let second = Sample(name: "b", count: 2, when: Date(timeIntervalSince1970: 100))
        try AtomicJSON.write(second, to: url)
        let reloaded = try AtomicJSON.decode(Sample.self, from: url)
        #expect(reloaded == second)
    }
}
