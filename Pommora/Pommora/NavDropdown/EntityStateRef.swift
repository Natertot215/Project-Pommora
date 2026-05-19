import Foundation

/// Flat wire-record for state.json entries (Recents + Favorites).
/// The `kind` is a raw String, not an enum, so old builds can decode
/// state.json containing unknown future kinds (forward-compat).
/// Equality + hash are by `(kind, id)` so a renamed entity stays the
/// same record; `title` is a denormalized cache refreshed on resolve.
struct EntityStateRef: Codable, Hashable, Sendable {
    let kind: String
    let id: String
    let title: String

    enum Kind: String {
        case page, vault, collection, space, topic, subtopic, item, agenda
    }

    var typedKind: Kind? { Kind(rawValue: kind) }

    init(kind: String, id: String, title: String) {
        self.kind = kind
        self.id = id
        self.title = title
    }

    init(kind: Kind, id: String, title: String) {
        self.init(kind: kind.rawValue, id: id, title: title)
    }

    static func == (lhs: EntityStateRef, rhs: EntityStateRef) -> Bool {
        lhs.kind == rhs.kind && lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(id)
    }
}
