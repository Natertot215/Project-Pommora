import Foundation

/// Reads and writes any `Codable` value as pretty-printed, sorted-keys, ISO-8601 JSON.
/// All writes use `Data.write(.atomic)` (temp-file + atomic rename under the hood).
///
/// Pommora discipline: every on-disk entity file routes through this helper so
/// files are deterministic on diff and human/agent-legible without app round-trip.
enum AtomicJSON {

    static func encode<T: Codable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func decode<T: Codable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    static func write<T: Codable>(_ value: T, to url: URL) throws {
        let data = try encode(value)
        try data.write(to: url, options: [.atomic])
    }
}
