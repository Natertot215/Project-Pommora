import Foundation

/// The single normalization for connection titles — used by the scanner, the
/// phantom key, resolution, and uniqueness so they never disagree. Trimmed + case-folded.
enum ConnectionTitle {
    nonisolated static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct ScannedConnection: Sendable, Equatable {
    let normalizedTitle: String
    let multiplicity: Int
    nonisolated init(normalizedTitle: String, multiplicity: Int) {
        self.normalizedTitle = normalizedTitle
        self.multiplicity = multiplicity
    }
}
