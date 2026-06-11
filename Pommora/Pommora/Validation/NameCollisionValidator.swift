import Foundation

/// Anything that occupies a filename slot inside a container (operational
/// entities — PageMeta, AgendaTask, AgendaEvent — and the organizational
/// entities + containers — Area, Topic, PageType, PageCollection). All
/// expose `id` (rename-safe identity) + `title` (the filename / folder stem).
/// Conformance is free — every type already carries these fields, so the
/// same-title collision rule lives in one place for all.
protocol NameCollisionCandidate {
    var id: String { get }
    var title: String { get }
}

// Operational entities (file-backed: `.md` / `.task.json` / `.event.json`).
extension PageMeta: NameCollisionCandidate {}
extension AgendaTask: NameCollisionCandidate {}
extension AgendaEvent: NameCollisionCandidate {}

// Organizational entities + containers (folder-backed; sibling-uniqueness is the
// same case-insensitive/trimmed rule). `Project` deliberately does NOT conform —
// its collision check adds a parent-scope dimension this validator doesn't model.
extension Area: NameCollisionCandidate {}
extension Topic: NameCollisionCandidate {}
extension PageType: NameCollisionCandidate {}
extension PageCollection: NameCollisionCandidate {}
extension PageSet: NameCollisionCandidate {}

/// One source of truth for the same-container name-collision rule.
///
/// **Why this exists:** `<title>.md` filenames are derived
/// from the title (no `title` field on disk — "filename = title" is locked).
/// Creating or renaming an entity to a title a *different* sibling already
/// holds in the same container would resolve to the same file path; the atomic
/// write then silently overwrites the other entity's file, destroying its body.
/// Rejecting on collision (locked decision — no auto-rename, no overwrite) is
/// the only safe behavior.
///
/// **Semantics:** case-insensitive, whitespace-trimmed comparison; an entity
/// whose `id` equals `excludingID` is ignored (renaming an entity to its OWN
/// current title is never a collision).
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

    /// Side-specific overload: runs the same collision detection but rethrows the
    /// caller's own `error` on collision instead of `NameCollisionError`. Hoists
    /// the `do { try validate(...) } catch is NameCollisionError { throw <side>.duplicateTitle }`
    /// remap that previously lived (identically) in every side's manager into a
    /// one-liner: each side passes its own `duplicateTitle` case so its public
    /// error contract + toast wording stay intact (DRY hard rule).
    static func validate<C: NameCollisionCandidate>(
        desiredTitle: String,
        siblings: [C],
        excludingID: String? = nil,
        else error: @autoclosure () -> any Error
    ) throws {
        do {
            try validate(desiredTitle: desiredTitle, siblings: siblings, excludingID: excludingID)
        } catch is NameCollisionError {
            throw error()
        }
    }
}

/// Shared error raised by `NameCollisionValidator`. Side managers map it to
/// their own `duplicateTitle` case (e.g. `PageCRUDError`) so the existing
/// per-side error contracts and toast messages stay intact.
enum NameCollisionError: Error, Equatable {
    case duplicateTitle
}
