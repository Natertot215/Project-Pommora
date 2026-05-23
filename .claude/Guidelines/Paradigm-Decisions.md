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
5. **Record the locked decision** in `History.md` (the canonical log for confirmed paradigm decisions and the surrounding session context).
