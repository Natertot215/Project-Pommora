import Foundation

/// The Crockford base32 alphabet (no I/L/O/U) shared by ULID generation and validation.
enum ULIDAlphabet {
    nonisolated static let crockford = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    nonisolated static let characters: [Character] = Array(crockford)
}
