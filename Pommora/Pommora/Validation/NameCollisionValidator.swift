import Foundation

/// Anything that occupies a filename slot inside a container (Item, PageMeta).
/// Both expose `id` (rename-safe identity) + `title` (the filename stem).
/// Conformance is free — both types already carry these fields.
protocol NameCollisionCandidate {
    var id: String { get }
    var title: String { get }
}

extension Item: NameCollisionCandidate {}
extension PageMeta: NameCollisionCandidate {}

/// One source of truth for the same-container name-collision rule shared by
/// Pages and Items.
///
/// **Why this exists:** `<title>.md` / `<title>.json` filenames are derived
/// from the title (no `title` field on disk — "filename = title" is locked).
/// Creating or renaming an entity to a title a *different* sibling already
/// holds in the same container would resolve to the same file path; the atomic
/// write then silently overwrites the other entity's file, destroying its body.
/// Rejecting on collision (locked decision — no auto-rename, no overwrite) is
/// the only safe behavior. Pages and Items use identical semantics, so the
/// detection lives here and both sides call it.
///
/// **Semantics (must match the Item side's historical `enforceTitleUniqueness`
/// exactly):** case-insensitive, whitespace-trimmed comparison; an entity whose
/// `id` equals `excludingID` is ignored (renaming an entity to its OWN current
/// title is never a collision).
enum NameCollisionValidator {

    /// Throws `NameCollisionError.duplicateTitle` when a *different* entity
    /// (`id != excludingID`) among `siblings` already holds `desiredTitle`
    /// (case-insensitive + trimmed). Each side catches this and rethrows its
    /// own side's `duplicateTitle` error to preserve its public error contract.
    ///
    /// - Parameters:
    ///   - desiredTitle: the new/proposed title (pre-trim is fine — trimmed here).
    ///   - siblings: the entities already in the target container.
    ///   - excludingID: the id of the entity being created/renamed; `nil` on
    ///     create (no self to exclude). Pass the entity's own id on rename so a
    ///     same-id rename (e.g. case-only / no-op) never false-positives.
    static func validate<C: NameCollisionCandidate>(
        desiredTitle: String,
        siblings: [C],
        excludingID: String? = nil
    ) throws {
        let needle = desiredTitle.trimmingCharacters(in: .whitespaces).lowercased()
        let conflict = siblings.contains { sibling in
            sibling.id != excludingID
                && sibling.title.trimmingCharacters(in: .whitespaces).lowercased() == needle
        }
        if conflict { throw NameCollisionError.duplicateTitle }
    }
}

/// Shared error raised by `NameCollisionValidator`. Side managers map it to
/// their own `duplicateTitle` case (`ItemCRUDError` / `PageCRUDError`) so the
/// existing per-side error contracts and toast messages stay intact.
enum NameCollisionError: Error, Equatable {
    case duplicateTitle
}
