## Phase C — Folder Reorg + Shared-Primitives Extraction

Establish the `Core` / `Components` shared layer and consolidate scattered primitives so DRY for views and utilities is the path of least resistance. Branch: `refactoring-phase-b` (stacked on B; not merged to `main` overnight).

### Autonomous-safe units (build-verifiable, behaviour-neutral)

Done unattended — each a green commit, verified by build.

**C1 — Folder reorg (move, don't rewrite).** Files relocate within the one module, so compilation is unaffected (PBXFileSystemSynchronizedRootGroup auto-tracks — quirk #2); behaviour-neutral.
- New `Core/`: absorb the one-file folders — `CRUD/` → `Core/CRUD/`, `Ordering/` → `Core/Ordering/`, `Filesystem/` → `Core/Filesystem/`.
- `Core/Formatters/`: move `IndexDateFormat` (from `Index`), `TimeFormat` + `DateFormat` (from `ViewSettings`).
- Misplaced singletons: `SavedConfig` (`Contexts` → `Configuration`), `ReservedTypeID` (`Vaults` → `Agenda`).
- `Components/Layout/`: extract `FlowLayout` (out of `MultiSelectChips.swift`).

**C2 — ULID alphabet single-source.** `ULID.swift` and `ULIDValidator.swift` both inline `"0123456789ABCDEFGHJKMNPQRSTVWXYZ"`; hoist to one constant both reference. Pure refactor.

**C3 — Route inline JSON coders through `AtomicJSON`.** `NexusIdentity` already uses `.iso8601`, so the switch is format-neutral. `AppState` only if it carries no `Date` fields (otherwise its on-disk shape would change — see deferred).

**C4 — Strip `how`-comments** in the files touched above, per the Studio comment rule (keep only the `why`). Nathan's directive.

### Deferred — needs Nathan's review (visual or paradigm-adjacent)

Not done unattended; left as findings:

- **magic-numbers → `PUI`** (~229 literal sizes/spacings/radii): visually neutral *only if* each `PUI` constant exactly equals the literal — a wrong map silently shifts pixels and the build can't catch it. Wants his eye.
- **`.hoverFill()` extraction** (the `DateTimePicker` inline hover): visual behaviour.
- **PropertyValue formatter consolidation**: routing `.datetime` through `IndexDateFormat` adds `.withFractionalSeconds`, changing on-disk decode of existing non-fractional datetimes — paradigm-adjacent.
- **AppState → AtomicJSON** *if* AppState has `Date` fields (would change its persisted shape).
