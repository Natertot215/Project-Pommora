import Foundation

/// Validates ULID strings (26-char Crockford base32, no I/L/O/U).
enum ULIDValidator {
    private static let crockfordAlphabet: Set<Character> = Set(ULIDAlphabet.crockford)

    static func isValid(_ id: String) -> Bool {
        guard id.count == 26 else { return false }
        return id.allSatisfy { crockfordAlphabet.contains($0) }
    }
}
