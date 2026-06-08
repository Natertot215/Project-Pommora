import Foundation
import Observation

/// View model for an interactive Item Window. Holds editable drafts of every
/// Item field plus a session-only `surfaced` set, and routes each field through
/// injected manager seams (rename / icon / body / property / delete) so the VM
/// stays free of any direct store dependency. Pure logic, fully unit-tested.
///
/// This file is the SKELETON only — stored state, init hydration, and the
/// `isFilled` predicate. The seam closures are stored now but the behavior
/// handlers that call them (and the body-debounce that uses `bodyTask`) land in
/// later tasks. Mirrors `PageEditorViewModel`'s idiom: `@MainActor @Observable`,
/// `item` re-held after a rename, seams as private/stored properties, a single
/// debounce constant.
@MainActor
@Observable
final class ItemWindowViewModel {
    /// The Item being edited. `var` because a successful rename in a later task
    /// re-holds it with the freshly-resolved Item from the manager (title + url
    /// change; id stays). Mutation should ONLY happen with a manager-resolved
    /// Item — never a hand-mutated copy (mirrors `PageEditorViewModel.page`).
    var item: Item

    /// Editable title. Hydrated from `item.title`; a later rename task commits it.
    var draftTitle: String
    /// Editable icon (SF Symbol name). `String?` mirrors `Item.icon`.
    var draftIcon: String?
    /// Editable body — the Item's capped Markdown description (`Item.description`).
    var draftBody: String
    /// Editable property values, keyed by `PropertyDefinition.id`.
    var draftProperties: [String: PropertyValue]
    /// Editable tier-1 Context relations (target ULIDs).
    var draftTier1: [String]
    /// Editable tier-2 Context relations (target ULIDs).
    var draftTier2: [String]
    /// Editable tier-3 Context relations (target ULIDs).
    var draftTier3: [String]

    /// Session-only set of property IDs the user has explicitly surfaced in this
    /// window (additive over the always-shown pinned set). Not persisted.
    var surfaced: Set<String> = []

    /// Property IDs pinned by the effective template (chip-eligible promoted
    /// properties). Computed once in `init`; immutable for the window's life.
    let pinnedIDs: Set<String>

    /// Surfaces a recoverable field-edit failure inline in the window. `String?`
    /// because the UI shows a message, not a typed error.
    var inlineError: String?
    /// Whether the body draft is over the Item description cap.
    var isOverCap = false
    /// Whether the side inspector pane is shown.
    var inspectorShown = true

    /// The Item's Type (schema source). Immutable for the window's life.
    let itemType: ItemType
    /// The Item's Collection, if it lives inside one. Immutable.
    let collection: ItemCollection?

    // MARK: - Manager seams (injected; later tasks call these)

    /// Persists a single property value change. `(propertyID, value)`.
    let onUpdateProperty: (String, PropertyValue) async throws -> Void
    /// Persists an icon change (nil clears the icon).
    let onUpdateIcon: (String?) async throws -> Void
    /// Persists a body (description) change.
    let onUpdateBody: (String) async throws -> Void
    /// Renames the Item's file; returns the freshly-resolved renamed Item.
    let onRename: (String) async throws -> Item
    /// Deletes the Item.
    let onDeleteItem: () async throws -> Void

    /// In-flight debounced body save. Declared now; a later body-debounce task
    /// owns its lifecycle (mirrors `PageEditorViewModel.saveTask`).
    private var bodyTask: Task<Void, Never>?

    /// Debounce window between a body edit and the disk write. Rapid edits within
    /// this window coalesce into one save (mirrors `PageEditorViewModel.debounce`).
    static let debounce: Duration = .milliseconds(300)

    init(
        item: Item,
        itemType: ItemType,
        collection: ItemCollection?,
        onUpdateProperty: @escaping (String, PropertyValue) async throws -> Void,
        onUpdateIcon: @escaping (String?) async throws -> Void,
        onUpdateBody: @escaping (String) async throws -> Void,
        onRename: @escaping (String) async throws -> Item,
        onDeleteItem: @escaping () async throws -> Void
    ) {
        self.item = item
        self.itemType = itemType
        self.collection = collection
        self.onUpdateProperty = onUpdateProperty
        self.onUpdateIcon = onUpdateIcon
        self.onUpdateBody = onUpdateBody
        self.onRename = onRename
        self.onDeleteItem = onDeleteItem

        // Hydrate every draft from the source Item.
        self.draftTitle = item.title
        self.draftIcon = item.icon
        self.draftBody = item.description
        self.draftProperties = item.properties
        self.draftTier1 = item.tier1
        self.draftTier2 = item.tier2
        self.draftTier3 = item.tier3

        // Pinned set = the chip-eligible promoted properties of the effective
        // template (Collection override → Type default), by id.
        self.pinnedIDs = Set(
            TemplateResolver.promotedForField(type: itemType, collection: collection)
                .map { $0.promotion.id }
        )
    }

    /// Whether a property value counts as "filled" (i.e. has user content). The
    /// falsy cases are the ways a value can exist yet carry nothing to show:
    /// - `nil` / `.null`     — no value at all.
    /// - `.multiSelect([])`  — a multi-select with no chosen options.
    /// - `.relation([])`     — a relation with no linked targets.
    /// - `.select("")`       — a single-select whose chosen option is the empty string.
    /// - `.status("")`       — a status whose chosen option is the empty string.
    /// Every other case (including `.number(0)`, `.checkbox(false)`, dates, urls,
    /// files, and `.lastEditedTime`) is filled. Tight exhaustive `switch` (HARD
    /// RULE): enumerate the falsy cases, `default` is filled.
    static func isFilled(_ v: PropertyValue?) -> Bool {
        switch v {
        case nil, .null, .multiSelect([]), .relation([]), .select(""), .status(""):
            return false
        default:
            return true
        }
    }

    /// Surfaces a schema property's inspector row so the user can then assign it a
    /// value. Writes NOTHING — the row appears empty until the user picks a value
    /// (which goes through handlePropertyChange). So no seam call here.
    func addProperty(_ id: String) {
        surfaced.insert(id)
    }

    /// Schema properties eligible for the "Add Property" menu: drop those already
    /// filled, pinned (they live on the chip row), reserved (id / tiers / status /
    /// type / timestamps), and the virtual last-edited-time.
    static func addableProperties(
        schema: [PropertyDefinition], filled: Set<String>, pinned: Set<String>
    ) -> [PropertyDefinition] {
        schema.filter { d in
            !filled.contains(d.id) && !pinned.contains(d.id)
                && !ReservedPropertyID.all.contains(d.id) && d.type != .lastEditedTime
        }
    }

    /// Applies a single property edit: mutate the in-memory draft synchronously,
    /// then fire one live save through the `onUpdateProperty` seam.
    ///
    /// Clearing (`value == .null`) removes the draft key AND surfaces the property
    /// so its (now-empty) inspector row stays visible — EXCEPT for a pinned
    /// property, which lives on the chip row and must never appear in the
    /// inspector, so a pinned-clear removes the draft without surfacing. Any
    /// non-null value just writes the draft (no surfacing — it's already filled).
    ///
    /// The original `value` (including `.null`) is always passed to the seam; the
    /// manager seam's gate converts a `.null` into on-disk key-removal. The save
    /// `Task` captures `self` STRONGLY: it's a one-shot save that must complete
    /// regardless of window lifecycle, and there's no retain cycle since the Task
    /// isn't stored. Being `@MainActor`, the Task inherits main-actor isolation,
    /// so reading `self.onUpdateProperty` is main-actor-safe.
    func handlePropertyChange(_ id: String, _ value: PropertyValue) {
        switch value {
        case .null:
            draftProperties.removeValue(forKey: id)
            if !pinnedIDs.contains(id) { surfaced.insert(id) }
        default:
            draftProperties[id] = value
        }
        Task { try? await self.onUpdateProperty(id, value) }
    }

    /// Applies a tier (Context-relation) edit: mutate the matching draft array
    /// synchronously, then fire one live save through the same `onUpdateProperty`
    /// seam used for ordinary properties.
    ///
    /// Tiers are stored as Item root arrays (`tier1` / `tier2` / `tier3`) but
    /// edited as `.relation` through the property seam — the reserved tier ID
    /// routes the manager back to the root array. The save ALWAYS sends
    /// `.relation(newIDs)`, even when empty: an empty relation clears the tier at
    /// its root; passing `.null` would be a bug (it would be read as key-removal,
    /// not an empty tier). `tier` is the fixed set 1...3 — a `switch` maps it to
    /// its draft + reserved ID, and any out-of-range caller is ignored (HARD RULE:
    /// tight exhaustive control flow). Strong `self` capture mirrors
    /// `handlePropertyChange`: a one-shot save with no stored Task, so no cycle.
    func handleTierChange(_ tier: Int, _ newIDs: [String]) {
        let reservedID: String
        switch tier {
        case 1:
            draftTier1 = newIDs
            reservedID = ReservedPropertyID.tier1
        case 2:
            draftTier2 = newIDs
            reservedID = ReservedPropertyID.tier2
        case 3:
            draftTier3 = newIDs
            reservedID = ReservedPropertyID.tier3
        default:
            return
        }
        Task { try? await self.onUpdateProperty(reservedID, .relation(newIDs)) }
    }

    /// Sets the draft icon and fires a one-shot live save through `onUpdateIcon`;
    /// `newIcon == nil` clears the icon. Strong `self` like the other one-shot handlers.
    func handleIconChange(_ newIcon: String?) {
        draftIcon = newIcon
        Task { try? await self.onUpdateIcon(newIcon) }
    }

    /// Records a body edit and (re)arms the debounced save.
    func handleBodyChange(_ newBody: String) {
        draftBody = newBody
        scheduleBodySave()
    }

    /// Cancels any pending body save and arms a fresh one `debounce` from now.
    /// Rapid edits coalesce into one write. [weak self] — cancellable/repeated,
    /// mirroring PageEditorViewModel.scheduleSave (NOT the one-shot handlers' strong self).
    private func scheduleBodySave() {
        bodyTask?.cancel()
        bodyTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.flushBodyNow()
        }
    }

    /// Writes the body draft immediately (the debounce safety net: window-close /
    /// Enter call this directly). Cancels the pending debounce task FIRST so a
    /// timer already mid-sleep can't double-write. Over the effective description
    /// cap, it sets `isOverCap` and skips the write; under cap it clears the flag
    /// and saves. The cap is resolved from the EFFECTIVE template (Collection
    /// override → Type), so a Set with its own descriptionCap colors correctly.
    func flushBodyNow() async {
        bodyTask?.cancel()
        let cap = ItemValidator.effectiveCap(
            template: TemplateResolver.effective(type: itemType, collection: collection))
        if draftBody.count > cap {
            isOverCap = true
            return
        }
        isOverCap = false
        try? await onUpdateBody(draftBody)
    }

    /// Deletes the Item via the delete seam. Async (awaited directly, like the
    /// title commit) — the view wraps it in a Task and dismisses on completion.
    func confirmDelete() async {
        try? await onDeleteItem()
    }

    /// Commits an inline title edit. Idempotent — fires from Enter, focus-loss,
    /// AND window-close, so the trimmed-equals-current guard makes every trigger
    /// after the first a no-op (and a whitespace-only edit a no-op too). On
    /// success it re-holds the manager-resolved renamed Item (id stays, title
    /// updates — never a hand-mutated copy, mirroring `PageEditorViewModel`). On
    /// failure (e.g. a filename collision) it sets `inlineError` and reverts
    /// `draftTitle` to the last good title.
    func handleTitleCommit() async {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != item.title else { return }
        do {
            let renamed = try await onRename(trimmed)
            self.item = renamed
            inlineError = nil
        } catch {
            inlineError = error.localizedDescription
            draftTitle = item.title
        }
    }
}
