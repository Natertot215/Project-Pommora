import Foundation

/// Thrown when a rename operation fails at the metadata-save step AND the
/// folder/file revert (to put the on-disk name back) also fails. The on-disk
/// state may be inconsistent — the file may be at the new name without the
/// matching metadata update. Callers should surface this to the user.
///
/// Used by every `rename*` method across AreaManager / TopicManager /
/// PageTypeManager / ContentManager that does two filesystem ops (rename + save).
struct RenameAtomicityError: LocalizedError {
    let saveError: any Error
    let revertError: any Error
    var errorDescription: String? {
        "Rename failed and the rollback also failed. The on-disk state may be inconsistent. Save error: \(saveError.localizedDescription). Revert error: \(revertError.localizedDescription)."
    }
}
