### Paradigm Decisions

Pommora's value depends on its on-disk format, schemas, and cross-entity contracts surviving a stack rebuild and a future cloud sync (load-bearing constraints #1 and #2). Code locking those shapes is **paradigm-solidifying** — once data exists in the wild, migrating is expensive.

#### Operating rule

**Stop and surface paradigm choices for Nathan's confirmation before the code lands** — use `AskUserQuestion` with concrete trade-offs and your recommendation.

Applies even when a written plan proposes one path — if you spot ambiguity, a real downside, or an alternative worth weighing, surface it first. Spec drift is acceptable; silent commitment is not.

#### What counts as paradigm-solidifying

- **On-disk schema shapes** — fields, types, naming conventions, snake_case vs camelCase per-key choices, nesting structures inside the per-kind sidecars (`_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`) / `.space.json` / `.project.json` / `.task.json` / `.event.json` / etc.
- **Wire encodings for ambiguous types** — tagged-object vs bare-string discrimination (e.g. `.relation` vs `.select` strings), date format choices (ISO-8601 vs Unix epoch vs human-readable), null-vs-missing semantics.
- **Identifier conventions** — ULID format, filename-as-title rule, ID-vs-title display split, relation key shape (e.g. `{"$rel": "..."}`).
- **Default values that become locked once data exists** — seeded per-kind sidecar shapes (`_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`), `defaultSeed()` outputs, default property catalog per Type.
- **File layout choices** — folder vs file boundaries for entities, filename extension conventions (`.project.json` vs `_project.json`), sidecar metadata file naming.
- **Cross-entity contracts** — tier1/tier2/tier3 array semantics, parent-pointer conventions, move-strip rules.
- **Error semantics at file load** — silent recovery (e.g. missing field → default) vs hard throw, malformed-file handling, validation timing.
- **Behavioral defaults that change user-visible outcomes downstream** — delete promote-vs-cascade default, filename collision handling (reject vs auto-suffix), move-across-Type property-strip behavior.

#### What does NOT count

- **Internal implementation choices** that don't affect on-disk shape — use of `@Observable` vs `ObservableObject`, value types vs reference types, manager-per-entity vs unified store.
- **UI structure** — view extraction, sheet vs popover, sidebar layout — these can be refactored freely without data migration.
- **Test strategy** — Swift Testing vs XCTest, test file organization, fixture patterns.
- **Build configuration** — Swift version, strict concurrency settings (already locked).
- **Naming of types in code** — internal CodingKeys names, struct rename refactors that preserve on-disk shape.

If in doubt, surface it. Better to overconfirm than retrofit.

#### Confirmation protocol

1. **Stop** before writing the locking line.
2. **State the choice in user-facing terms** — on-disk shape, user-visible behavior, migration cost. Not jargon.
3. **Present 2–3 options** with concrete on-disk samples. Lead with your recommendation.
4. **Wait for confirmation.** Update the spec/plan before dispatching implementation.
5. **Record the locked decision** in `History.md` (the canonical log for confirmed paradigm decisions and the surrounding session context), then add a one-line entry to the registry below.

#### Registry

Numbered, chronological. Citations elsewhere ("paradigm decision #N") resolve here. Each entry is the decision plus a one-line rationale; full session context lives in `History.md`.

1. **`PropertyValue.relation` encodes as an array of tagged objects `[{"$rel": "<ULID>"}]`** (always multi-value; a single link is a one-element array), not bare strings — relation edges stay legible to external agents and the graph indexer without consulting a Type's schema (constraint #3).
2. **Collections persist a sidecar** (`_pagecollection.json` / `_itemcollection.json`, carrying id + parent-Type id + ordering) — the parent relation is explicit on-disk rather than inferred from folder nesting.
3. **SF Symbol picker = the `xnth97/SymbolPicker` SPM dep wrapped behind Pommora's own `IconPickerSheet` / `IconPickerField`** — the wrapper isolates call sites, so swapping libraries is a single-file rewrite.
4. **Stub-and-progressively-replace is the execution strategy** for branch-spanning plans with forward dependencies — each task ships green standalone with throwaway in-file stubs that later tasks replace in place, rather than one batch-commit-at-end where a single break contaminates the whole batch.
5. **Sidebar creation is via right-click context menus scoped to the cursor**, not "+ New" buttons — right-clicking a row binds "New X" to that exact entity, keeping the entry point unambiguous.
6. **Sidebar selection chrome lives at the row-file level via `.listRowBackground(SelectionChrome(...))`**, not in-content `.background` — the row-level background covers the disclosure-chevron gutter, and an in-content `.background` regressed a launch crash in `OutlineListCoordinator.recursivelyDiffRows`.
7. **Pages editor stack** — superseded. The locked direction was originally Tiptap (ProseMirror) in a WKWebView; the editor shipped instead as **TextKit 2 + Apple `swift-markdown` + the vendored `swift-markdown-engine`** (native NSTextView, no web view). Spec → `// Features//PageEditor.md`; engine rules → `Markdown.md`.

8. **Relations are always multi-value** — the single/multi `allows_multiple` toggle is gone; every relation property holds an array (see #1), so one uniform value shape exists on disk and in the editor.
9. **The relation schema target uses the `relation_target` key with a fixed case set** — user-creatable targets are `page_type` / `item_type` / `agenda_tasks` / `agenda_events`; `context_tier` (tiers 1/2/3) is internal-only; `page_collection` / `item_collection` are read-tolerated for adoption + rewritten to their parent Type on migration, never user-selectable.
10. **Tiers are relations** — `tier1` / `tier2` / `tier3` (root frontmatter arrays) are the same edge type as relation properties; both emit into the SQLite `relations` table and share one reverse-lookup path (`IndexQuery.incomingRelations`). There is no separate tier-links table.
11. **Deleting a Context cascades source-side** — every operational entity's `tier1/2/3` reference to the deleted Context is removed from its own file (not promoted, not orphaned). Orchestrated at the delete call site, which holds the content-manager references.
12. **Agenda Tasks and Events are valid relation targets** — relation properties (and paired reverse relations) may target the Agenda Tasks or Agenda Events collections, the same as Page Types and Item Types.

> **Note on numbering.** This registry's cross-project entries run #1–#12. A few cross-references in other docs use *plan-local* numbering from their own source lists — notably `History.md`'s "locked decision #12" (the View-Settings plan's list, recorded in a Handoff), which is unrelated to registry #12. Resolve a plan-local citation against its source plan + `History.md`; resolve a bare "paradigm decision #N" against this registry. The registry is extended only when a genuinely cross-project paradigm decision is ratified.
