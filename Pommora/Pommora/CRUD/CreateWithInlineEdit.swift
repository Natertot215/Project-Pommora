import Foundation

/// Orchestrates the system-wide stub-and-inline-rename CRUD flow (paradigm
/// shift superseding the modal `New*Sheet.swift` pattern). Every "New X"
/// trigger across Pommora — PageType, PageCollection, Folder, Page, ItemType,
/// ItemCollection, Item, and the Context tier (Space, Topic, Project) —
/// funnels through this helper so the create-then-edit sequence is uniform.
///
/// Usage from a sidebar row or detail-view footer:
/// ```swift
/// Task {
///     do {
///         _ = try await CreateWithInlineEdit.run(
///             create: {
///                 try await manager.createPageCollection(
///                     name: DefaultTitleResolver.resolve(
///                         label: labels.pageCollection.singular,
///                         existingTitles: existing.map(\.title)
///                     ),
///                     inPageType: parent
///                 )
///             },
///             onCreate: { newCollection in
///                 editingID = newCollection.id
///             }
///         )
///     } catch {
///         // Manager has set pendingError → toast renders. Bindings untouched.
///     }
/// }
/// ```
///
/// The caller writes the `editingID` binding inside `onCreate`. The matching
/// row file (e.g. `PageCollectionRow`) gates rename-mode on
/// `editingID == entity.id`; `RenameableRow.onAppear` then auto-focuses its
/// `TextField`. Esc and click-away both call the row's `cancel()`, which
/// resets `editingID` to `nil` — the stub entity stays created with the
/// default title (deletable via context menu) per the locked Esc semantics.
enum CreateWithInlineEdit {

    /// Invoke `create`; if it succeeds, run `onCreate` with the resulting
    /// entity and return it. If `create` throws, `onCreate` is NOT invoked and
    /// the error propagates to the caller (whose manager has already populated
    /// `pendingError` for the sidebar toast).
    ///
    /// - Parameters:
    ///   - create: Async manager-create closure that produces a freshly
    ///     persisted entity. Typical body: `try await manager.createX(...)`.
    ///   - onCreate: Invoked once, synchronously after a successful create,
    ///     with the new entity. Callers flip `editingID` (and any other UI
    ///     bindings like sidebar `selection`) here so the matching row enters
    ///     rename mode and the `RenameableRow.onAppear` focus hand-off fires.
    /// - Returns: The entity returned by `create`.
    /// - Throws: Re-throws any error from `create` verbatim.
    @discardableResult
    static func run<Entity>(
        create: () async throws -> Entity,
        onCreate: (Entity) -> Void
    ) async throws -> Entity {
        let entity = try await create()
        onCreate(entity)
        return entity
    }
}
