import Foundation

enum FilenameSafety {
    static let invalidCharacters: Set<Character> = ["/", "\\", ":"]

    /// Trims `raw`, then enforces the two filename-safety rules every entity validator
    /// shares. The caller supplies its own error type so the public contract is unchanged.
    static func validatedTitle(
        _ raw: String,
        empty: @autoclosure () -> any Error,
        invalidCharacters: @autoclosure () -> any Error
    ) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw empty() }
        guard trimmed.allSatisfy({ !Self.invalidCharacters.contains($0) }) else { throw invalidCharacters() }
        return trimmed
    }
}
