### CRUD Patterns

SwiftUI patterns for per-entity CRUD UI — file format → sidebar UI → validation. Guideline, not enforcement.

---

#### Preview prerequisite — one shared primitive

"Open in preview" is a generic affordance backed by **one shared primitive** — the `PagePreview` child panel opened via the preview-open path (spec → `Features/Pages.md` § "Opening behavior") — not a per-feature one.

**Rule:** for any entity kind (Page, Page Type, Page Collection, and each Context tier, Task, Event), preview support for that kind ships on the shared primitive **before** any "open in preview" UI is wired for it. CRUD may land independently; the preview affordance waits. Half-wired feature-specific window plumbing rots when requirements shift — one project-wide primitive, bolt feature surfaces onto it. Today only Pages have preview support, routed per-vault via `open_in`.

---

#### Manager pattern — per entity, `@MainActor @Observable`

Every new entity (each Context tier, Page Type, Page Collection, Page, Task, Event, Homepage, Settings, …) gets its own `@MainActor @Observable final class` manager mirroring `NexusManager`'s shape. Per-entity, not one unified store — this narrows state-driven updates so changing one entity doesn't re-evaluate unrelated sidebar sections.

The shape: a `private(set)` array of the entity, a `pendingError: (any Error)?`, an injected `Nexus`, and `async`/`async throws` methods for `loadAll`, `create` (`@discardableResult`, returns the new entity), `rename`, `update*`, and `delete`.

Inject the active Nexus at construction; **the init does NOT kick its own load** — the parent view drives loading via `.onChange(of:initial:true)` on `NexusManager.currentNexus`, where `initial: true` covers the nil → Nexus transition. Keeping load out of init avoids racing the parent's `.onChange`.

**`pendingError` scope:** set from `loadAll`/`load` AND from every CRUD method — each catch block assigns `self.pendingError = error` before rethrowing. A sidebar-level toast (`SidebarToast`) surfaces it transiently, so failed context-menu renames/deletes are never silent. Sheet-level forms additionally use a per-view error-message `@State` for inline display at the point of edit.

**Property-schema mutation is shared, not per-manager.** The five schema methods — add / rename / delete / reorder property + change type — are NOT reimplemented per manager. They live in two shared `@MainActor` services: a per-type schema service (Page Type, keyed by type ID) and a singleton schema service (Task / Event, single schema). Each manager supplies a small per-side adapter (metadata URL, concrete error enum, member-file strip, index owning-kind) and keeps its exact public signatures + concrete error enum + the `pendingError`-set-then-rethrow wrapper via a one-line delegator. Entity-level CRUD (create/rename/delete the Type or Collection itself) stays per-manager.

---

#### Codable file types — `load(from:)` + `save(to:)` mirror `NexusIdentity`

Every Codable entity file follows `NexusIdentity`'s shape: a `Codable, Equatable, Identifiable, Hashable, Sendable` struct with an `id` (ULID), title derived from filename on load, and a static `load(from:)` / instance `save(to:)` pair that route through the shared `AtomicJSON` codec.

---

#### Atomic JSON write — `Data.write(.atomic)` is enough

`AtomicJSON` is the single JSON read/write path. Encode uses pretty-printed + sorted keys + ISO-8601 dates; decode mirrors it. `Data.write(to:options:[.atomic])` writes to a temp file + atomic rename under the hood — **no separate `.tmp` helper needed**. Reuse `AtomicJSON` for every Codable entity file. Output stays human-inspectable and agent-legible without an app round-trip.

---

#### YAML frontmatter + body — `AtomicYAMLMarkdown` (preserving merge-on-write)

Yams (`github.com/jpsim/Yams`, MIT) backs the `AtomicYAMLMarkdown` codec — the single read/write path for Pages (`.md` frontmatter + body). No first-party Apple solution; `apple/swift-markdown` handles body but not frontmatter.

**Writes preserve foreign frontmatter by value — never cull.** A typed encode only emits the keys it models, so serializing that alone would drop any plugin/foreign key an external tool wrote onto the file. So every full-frontmatter write **merges the typed struct's keys back over the existing on-disk frontmatter** rather than replacing it: encode the modeled keys; read the existing file; for each on-disk key, substitute the typed value if it's a modeled key (or drop it if the typed value cleared it) and pass it through unchanged if it's foreign; then append modeled keys not already present and envelope with `---` fences + body.

- The modeled-key set is the entity's own coding keys — everything else rides along untouched.
- The preservation read targets the URL the entity was read from. A rename renames old→new **first**, then saves to the new URL, so preservation reads the post-rename file.
- Yams round-trips by value — a foreign file's flow→block style reflows and comments/anchors drop on first re-serialization. Content is safe; exact styling is not.

This applies on every Page write path. Agenda (`.task.json` / `.event.json`) and sidecars stay JSON via `AtomicJSON`.

---

#### Sidebar pattern — extend existing `SidebarView`

`SidebarView` already uses `List` + `Section(isExpanded:)` + `DisclosureGroup` + the locked `SelectableRow` selection language. **No new sidebar architecture needed** — swap placeholders for real data from each manager as it lands.

Each section is its own `struct: View` (not a computed property) so SwiftUI can skip body re-evaluation when inputs don't change — pattern from `swiftui-expert-skill/references/view-structure.md` ("Extract Subviews, Not Computed Properties").

Creation triggers use the stub-and-inline-rename coordinator (`Core/CRUD/CreateWithInlineEdit.swift` + `Core/CRUD/DefaultTitleResolver.swift`) — there is no creation-sheet enum and no `.sheet(item:)` switch. Each manager's `create*` returns the new entity via `@discardableResult`; the coordinator flips the matching row into rename mode via shared `editingID` + `justCreatedID` bindings owned by `ContentView`.

---

#### Folder + file atomicity (multi-step filesystem ops)

Creating a folder-backed entity (a Context tier, a Vault) is **two steps** — create the folder, then write the metadata sidecar. `Data.write(.atomic)` only atomicizes the write; the combined op needs **best-effort rollback** on failure + **idempotent recovery** on load.

The pattern: create the directory, then in a `do` block build the entity and write its sidecar; on any thrown error in that block, `try?`-remove the orphaned folder before rethrowing.

**Idempotent recovery on load:** if `loadAll()` finds a folder under the tier directory without its sidecar inside, skip silently — treat it as user-manual organization to be repaired in Finder. **Folder rename** uses `FileManager.moveItem(at:to:)` — atomic on the same volume (always true for nexus contents).

##### Rename atomicity — rename-first-then-write-metadata, rollback on failure

Renames that touch two filesystem ops (folder/file rename + metadata save) follow one uniform pattern across **every `rename*` / `move*` site on the entity managers**: rename the folder/file first → write metadata → if the metadata write fails, roll the rename back → if the rollback ALSO fails, throw a `RenameAtomicityError` (a `LocalizedError` carrying both the save error and the revert error). Managers set `pendingError` on that unrecoverable case before rethrowing. The remaining gap is the rare double-failure (both rename and rollback fail) — surfaced via `RenameAtomicityError` rather than silently leaving divergent on-disk state.

##### Cover + banner assets — copy-then-write, delete-AFTER-write

Page `cover` and container `banner` are the same asset-CRUD shape — a nexus-relative path string on the entity (`cover` on Page frontmatter; `banner` on the container sidecar). The image lives under the nexus assets directory, keyed by entity ID; both flows share `CoverAssetStore` (collision-safe naming + a hard-cap size guard) and `AssetURLResolver` for path→URL (DRY).

- **Container banner CRUD routes through the Page Type manager's set-banner method** (handles both container kinds via a fresh read-modify-write of the sidecar — `banner` isn't indexed, so no SQLite upsert). Page covers persist via the page-frontmatter update path.
- **Set / Change — copy first, then write the field.** The store copies the source into the entity's asset folder **inside the security-scoped window** (the synchronous copy completes before the `defer` closes the scope; only the field-persist hops to a `Task`). The returned relative path is written to `cover` / `banner` only after the copy succeeds.
- **Delete-AFTER-write discipline.** On Change or Remove, the new path (or `nil`) is written FIRST, and the store removes the previously-referenced asset **only after that write succeeds** — so a failed write never leaves the field pointing at a deleted file, and never orphans the old file before the new one commits. Delete is containment-guarded (only removes files under the entity's own asset dir) and no-ops on nil/missing.
- **UI mirror.** The container banner view shows a hover-revealed "Add Banner" affordance in the empty state and a Change / Remove context menu when set — mirroring the page-level cover flow. Copy failures surface via the manager's `pendingError` → `SidebarToast`.

---

#### Validation — pure functions per entity

Enforced at the manager layer, before write. Each entity has a pure validator enum exposing a `validate(...)` that throws a typed `ValidationError` (empty title, invalid characters, duplicate title). It trims first, checks the **trimmed** value against the empty and invalid-character rules (consistently — never validate the raw input after trimming for emptiness), and rejects case-insensitive title collisions against existing entities, excluding the entity being edited.

Tier-parent validation needs cross-entity lookup (a Project's parent Topic ID must resolve). **Locked Swift 6 pattern:** managers take a `contextProvider: @MainActor @escaping () -> NexusContext` closure at init returning a fresh snapshot per call. `NexusContext`'s inner lookup closures are `@Sendable` (they cross into off-actor validators), so capture `Sendable` value-type arrays into local `let`s at the outer `@MainActor` scope before building the context.

`NexusEnvironment.init` is where this snapshot trick lives: it constructs every per-Nexus manager and, for managers needing lookups, builds the `@MainActor` closure that reads each manager's live array into a local, then returns a `NexusContext` of per-tier lookup closures capturing those locals.

**One-shot only:** invoked per-validate-call and thrown away. **Do not store** in a long-lived closure (background indexer, search index, etc.) — the snapshot would go stale. A higher-level coordinator aggregating all managers is a later pass; for now the per-manager `contextProvider` closure is the pattern.

---

#### Sandbox + security-scoped access — already solved

`NexusManager` owns the `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` lifecycle. New file writes inside the nexus **inherit access from the active scope** — no per-write bookmark needed.

**Discipline:** new entity managers must NOT call `startAccessing` independently — they assume `NexusManager` holds the active scope and read `nexusURL` from the active `Nexus`, writing within that tree.

EventKit (Agenda) is a separate access flow: its own sandbox entitlement + Info.plist usage descriptions + `requestFullAccessTo*` APIs, NOT the file-r/w resource scope. Detail → `Features/Agenda.md`.

---

#### SF Symbol picker — Pommora-native `IconPicker`

Pommora's own `IconPicker` (`Properties/IconPicker/`) is the icon chooser everywhere — a compact Liquid-Glass dropdown over the full SF Symbols catalog (`IconCatalog`, bundled as source) with search + Saved/favorites (`IconFavorites`, app-level UserDefaults). It replaced a third-party SPM picker (History.md) that hardcoded its macOS frame and kept its catalog `internal` — neither resizable nor re-skinnable.

**Present it via the one DRY modifier**, anchored to the icon button. The modifier bakes in `.presentationBackground(.clear)` to strip the system popover's own material so only the picker's own glass shows — no double-glass. The modifier takes an `isPresented` binding and a `Binding<String?>` symbol whose setter commits the pick; nil clears it (the picker's "Remove Icon" row, shown only when an icon is set). The picker writes the binding and dismisses on pick.

**Edit-Icon on existing rows** routes through `IconPickerSheet`, which hosts the picker and dispatches the chosen symbol to the right manager's icon-update method via an icon-target switch (one case per entity kind). **Its `@Environment` managers must be reachable wherever it's presented** — a `.sheet` inherits the host's environment, so every NavigationSplitView column that can present it must inject every manager it reads (quirk #15; a manager missing from the detail-column chain crashes the detail-table Edit Icon).

**Create flows** present the picker through the same DRY `iconPickerPopover` modifier, anchored to the icon button.

---

#### Inline editing principle — managers own writes, embeds dispatch to managers

Every embedded view (Context page, Homepage) is **a live, fully-editable view of its source** — not a snapshot.

- The block stores the **reference** (source entity ID + view config + filters), not a snapshot.
- Edits route through the source entity's manager (e.g. checking off a Task in an embed calls the Task manager's toggle).
- The manager atomically writes the source file.
- The file watcher catches the change → SQLite re-indexes → all embedded views refresh live.

**No separate "embed-edit path" vs "primary-surface edit path."** Same manager, same methods. One source of truth per entity. Detail → `Features/Domain-Model.md → Inline editing principle`.

---

#### Inline property editing + picker hosting

How a window / panel / detail surface hosts editable relation, status, and tier values. The reusable units let any future surface wire property editing by recipe instead of reinventing it.

- **`PropertyEditorRow`** is the per-property editor row. Hosts pass a property definition + a `@Binding value`, plus (for context links) an optional index + relation-display resolver (both defaulted `nil`, so non-relation call sites compile unchanged). It renders the right editor per property type: relation → `ContextValueEditor`, status → single-select chip dropdown.
- **`ContextValueEditor`** is the inline context-link/tier editor: shows the current value as a `ContextChip` icon+title (or an "Add" affordance) and presents the grouped `ContextPicker` in a **chromeless popover** on tap (`.presentationBackground(.clear)`). **The picker owns its own fixed frame**, so the chromeless popover can't collapse — never rely on the popover to size it. Tiers reuse it directly with a tier scope.
- **Value-commit contract — the host owns persistence.** `ContextValueEditor` writes the new ID array back through its `@Binding`; the host's setter routes to its manager (the page-frontmatter / property update path, or a view model's tier-change → debounced save). The editor never knows the manager — binding-in, binding-out.
- **Env (quirk #16).** The editor needs the index (picker candidate query) + the display resolver (current-value chips). Pass them **explicitly as params** when the host is a sheet/popover — sheet env-inheritance is the classic SIGTRAP trap; read via `@Environment` only when the host sits directly in the `.detail` chain that injects them.
- **Current hosts:** `FrontmatterInspector`, mounted on both surfaces — the main-pane Page editor (full scale) and the PagePreview panel (compact) — editable tiers + relation/status properties, persisting through the shared `FrontmatterInspectorViewModel` path.

---

#### Modern SwiftUI API hygiene

Follow `swiftui-expert-skill/references/latest-apis.md` for current API choices (`@Observable`/`@State`/`@Bindable`, `.foregroundStyle`, `.clipShape(.rect(cornerRadius:))`, `.onChange(of:)` two-param closures, `NavigationStack`/`NavigationSplitView`, `@Entry`, and the rest). No back-deployment burden.
