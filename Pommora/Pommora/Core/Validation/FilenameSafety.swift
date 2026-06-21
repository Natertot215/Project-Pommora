import Foundation

enum FilenameSafety {
    static let invalidCharacters: Set<Character> = ["/", "\\", ":"]

    /// Trims `raw`, then enforces the two filename-safety rules every entity validator
    /// shares. The caller supplies its own error type so the public contract is unchanged;
    /// `E` is inferred from the supplied errors, letting callers propagate typed throws.
    static func validatedTitle<E: Error>(
        _ raw: String,
        empty: @autoclosure () -> E,
        invalidCharacters: @autoclosure () -> E
    ) throws(E) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw empty() }
        guard trimmed.allSatisfy({ !Self.invalidCharacters.contains($0) }) else { throw invalidCharacters() }
        return trimmed
    }
}
