import Foundation

/// The single normalization for connection titles — used by the scanner, the
/// phantom key, resolution, and uniqueness so they never disagree. Trimmed + case-folded.
enum ConnectionTitle {
    nonisolated static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum ConnectionSyntax: String, Sendable, Equatable {
    case page   // [[ ]]
    case item   // {{ }}
    /// The target entity kind this syntax resolves to (stored in `connections.target_kind`).
    nonisolated var targetKind: String { self == .page ? "page" : "item" }
}

struct ScannedConnection: Sendable, Equatable {
    let normalizedTitle: String
    let syntax: ConnectionSyntax
    let multiplicity: Int
    nonisolated init(normalizedTitle: String, syntax: ConnectionSyntax, multiplicity: Int) {
        self.normalizedTitle = normalizedTitle
        self.syntax = syntax
        self.multiplicity = multiplicity
    }
}
