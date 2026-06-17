## Swift Improvements Surfaced by the React Rebuild

A verified register of Swift-side over-complications and minor quality gaps that building the same product from scratch in React exposed. This is **input for a separate Swift agent**, not a step-by-step plan.

**How to use it.** Each item is code-grounded; `file:line` references are accurate as of 2026-06-17 but the Swift tree moves — **re-ground every reference before changing it**. Plan and adversarially review each fix on its own (`rules/Review-Discipline.md`); this doc is the *what* and *why*, not the *how*. The big wins are the DRY collapses (Flags 3–6); the rest are minor or hardening.

**Provenance.** Gathered from the React `Data-Layer-Build-Log.md` per-phase "Swift delta" notes + a Swift-bloat research pass, verified against `Pommora/Pommora/` by a dispatched agent. The frontmatter/sidecar model below and Flags 1, 3 were independently re-verified against the real code, and the sidecar question was adjudicated with Nathan (see below).

### The frontmatter / sidecar model (adjudicated 2026-06-17 — read first)

An earlier framing — "Swift wipes non-conforming frontmatter on write" — conflated two surfaces Pommora treats **deliberately differently:**

- **Page `.md` frontmatter keeps everything, regardless.** The page file is the data surface: foreign root keys and all property values persist across writes. Swift honors this — `PageFile.save` merges over the existing file via `AtomicYAMLMarkdown` (`PageFile.swift:33-35`, `AtomicYAMLMarkdown.swift:117-146`), passing foreign keys through untouched. (It does drop YAML *comments* — Flag 1.)
- **The sidecar is the schema/lens, not a data store.** A Type's sidecar holds `property_definitions`; that schema validates the page's YAML to identify **which frontmatter keys are Pommora properties** — "yes, this was created here, show it as a typed property." Keys present in the frontmatter but absent from the schema stay in the `.md`; they simply aren't surfaced as typed properties.
- **Therefore a sidecar re-emitting only its modeled keys is BY DESIGN, not data loss.** Sidecars are controlled Pommora schema/config files; arbitrary external data belongs in markdown frontmatter, which preserves it.

**Net: there is no urgent frontmatter data-loss bug.** The code observation "JSON sidecars drop unknown keys" (`AtomicJSON.swift:24-27`, `Area.swift:33-57`) is real but **intended** — do not "fix" it. The React build's `z.looseObject` on sidecars is a harmless *defensive* extra; its build-log framing ("closes Swift's JSON-sidecar data-loss gap") is overstated against this model. The only real preservation gap is the minor one below.

---

### Frontmatter & values (minor)

#### 1 · Page `.md` preservation drops YAML comments (+ may reflow style) — MINOR · CONFIRMED IN CODE

The page path preserves foreign **values** but via a hand-rolled Yams `Node` merge that round-trips by value only: comments and anchors drop, and flow↔block style may reflow. Since the rule is "markdown keeps all frontmatter regardless," comments are the one thing that slips through "regardless."

- **Evidence:** `AtomicIO/AtomicYAMLMarkdown.swift:117-146` (the `mergedData` Node merge); the team's own test asserts the loss — `FrontmatterPreservationTests.swift:136` ("Value preserved (style may reflow block↔flow, comments may drop)").
- **React parity:** the `yaml` Document API (`parseDocument`/`set`/`delete`/`toString`) touches only modeled nodes, so foreign keys **and comments** survive natively (`React/src/main/io/pageFile.ts`).
- **Why it matters:** minor — comments aren't property data, and the ~70-line `Node` merge is incidental complexity a Document-API approach would remove. Weigh the fix against the churn; low priority.
- **Fix sketch:** adopt a comment-preserving YAML edit. Yams has no Document API, so this likely means a different YAML lib or accepting the limitation.

#### 2 · `PropertyValue` type is re-sniffed from JSON shape on every read — FRAGILITY · CONFIRMED IN CODE

`PropertyValue.init(from:)` infers a property's kind purely from on-disk shape via an ordered cascade of `try?` decodes; the declared type in the schema is never consulted. This is in mild tension with the model above — the *schema* is meant to be the authority on what a property is.

- **Evidence:** `Vaults/PropertyValue.swift:50-131` (the shape-sniffing decode); `Content/PageFrontmatter.swift:79` (decodes `[String: PropertyValue]` with no schema context). The branch **order** is load-bearing (relation arrays before `[FileRef]`, non-empty before empty, …) and un-asserted — a reorder mis-types values with no error.
- **React parity:** same on-disk shapes and same locked precedence (it had to match byte-for-byte), but the codec is a small pure-function pair, and the precedence is pinned by a table-driven round-trip fixture.
- **Honest scope:** the *on-disk shapes are shared*, so this is "same behavior, riskier implementation," not a behavior gap. Treat as hardening.
- **Fix sketch:** keep the codec but add an exhaustive table-driven round-trip test over every variant plus the legacy single-`$rel` and empty-array edges, so a precedence reorder fails loudly. Optionally consult the schema type on read where available.

---

### Over-complication / DRY (the real wins — verified duplication)

#### 3 · `PerTypeSchemaService` + `SingletonSchemaService` are near-duplicate — ~690 LOC · CONFIRMED IN CODE

Two files implement the identical five schema-mutation ops (`addProperty`/`renameProperty`/`deleteProperty`/`reorderProperty`/`changeType`), each with its own adapter protocol — and the code says so.

- **Evidence:** `Properties/PerTypeSchemaService.swift` (354 LOC) + `Properties/SingletonSchemaService.swift` (335 LOC); the latter's header (`:7-14`) states the bodies are "byte-identical modulo a handful of mechanical token swaps."
- **React parity:** one parameterized `crud/schema.ts` over a `SchemaTarget` (page vs agenda) serves both.
- **Fix sketch:** merge into one generic schema-ops type parameterized over a single `SchemaTarget`/adapter (per-type vs singleton differ only in read/commit + the `canDelete` builtin guard).

#### 4 · Three Context managers (Area/Topic/Project) are triplicated CRUD ladders — ~500 LOC · CONFIRMED IN CODE

`AreaManager`, `TopicManager`, `ProjectManager` each re-implement the same `create/rename/delete/reorder/updateIcon/loadAll/readPersistedOrder` ladder with byte-identical rename-atomicity rollback, diverging only in entity type + sidecar filename (+ `updateColor`, Area-only).

- **Evidence:** `Contexts/AreaManager.swift` (175 LOC), `TopicManager.swift` (166 LOC), `ProjectManager.swift` (159 LOC); rollback blocks match (AreaManager:109-123 ≈ TopicManager:122-135 ≈ ProjectManager:95-105). No shared base/protocol for entity CRUD.
- **React parity:** one generic `crud/folderEntity.ts` serves all six folder-shaped entities.
- **Fix sketch:** extract a generic folder-entity CRUD core (protocol + shared extension, or a generic over an `entity + sidecar-filename + index-kind` descriptor); the three context managers **and the two Vault managers** become thin conformances.

#### 5 · Agenda Task/Event managers duplicate item CRUD — ~260 LOC · CONFIRMED IN CODE

`AgendaTaskManager` and `AgendaEventManager` re-implement parallel item CRUD (`create/update/rename/delete/unlinkTier`), differing only in type names + file extension. (Their *schema* ops already share `SingletonSchemaService`; only item CRUD is still duplicated.)

- **Evidence:** `Agenda/AgendaTaskManager.swift` + `AgendaEventManager.swift`; rename (Task:178-223 ≈ Event:183-228) and `unlinkTier` (Task:264-306 ≈ Event:269-312) near-identical.
- **React parity:** one `crud/agendaEntity.ts` factory for both kinds.
- **Fix sketch:** fold both into one agenda-item CRUD core parameterized over the kind (suffix, schema, index table) — the same pattern as Flag 4.

#### 6 · `LenientFrontmatterShape` is a hand-maintained second copy of `PageFrontmatter` — DRIFT RISK · CONFIRMED IN CODE

`PageFile.swift` carries a private `LenientFrontmatterShape` mirroring `PageFrontmatter` with all-optional fields, just for the adoption/lenient read path — a duplicate shape + duplicate `CodingKeys` kept in sync by hand.

- **Evidence:** `Content/PageFile.swift:86-99` (the duplicate struct), used at `:50-56`.
- **React parity:** one zod schema with `.partial()`/`.default()`/`.catch()` serves both strict and lenient reads; `z.infer` is the single type.
- **Why it matters:** add a field to `PageFrontmatter`, forget `LenientFrontmatterShape`, and lenient reads silently drop it.
- **Fix sketch:** derive the lenient read from the same model (decode `PageFrontmatter` with all-optional tolerance, or generate one shape from the other) instead of a parallel struct.

---

### Architectural / robustness (lower priority)

#### 7 · GRDB forces 10 `*Snapshot` mirror structs + a two-phase MainActor index build — ARCHITECTURAL · CONFIRMED IN CODE

Ten `*Snapshot` structs exist purely as `Sendable` GRDB record mirrors (so data can cross the `@MainActor` boundary into the write closure); the cold build is a two-phase "walk on MainActor → write in `@Sendable` closure" dance.

- **Evidence:** `Index/IndexBuilder.swift:8-100` (the 10 snapshots) + `:126-141` (two-phase build).
- **Honest scope:** largely a *consequence of GRDB + Swift concurrency*, not a freestanding bug. Replacing GRDB is a big lift — flag as architectural, low-urgency; don't action casually.
- **Fix sketch:** long-term, drop GRDB's record layer for hand-written parametrized SQL so domain types populate parameters directly, removing the snapshots.

#### 8 · Connection resolution + rename-cascade require the SQLite index (no pure fallback) — ROBUSTNESS · CONFIRMED IN CODE

Wiki-link resolution goes through `IndexQuery.resolveUniqueEntity` (a synchronous SQLite read); the rename cascade finds inbound links via `IndexQuery.incomingConnections`. Connection correctness depends on the index being present + fresh.

- **Evidence:** `Connections/ConnectionResolver.swift:5-16`; `Index/IndexQuery.swift:310-320`; `Connections/ConnectionCascade.swift:37-40`.
- **React parity:** a pure in-memory Map engine resolves links; the index is a pure accelerator, never load-bearing.
- **Caveat:** Swift's resolver is **sync because it runs inside the TextKit layout pass** — a real platform constraint. A pure-Map rewrite must still answer synchronously.
- **Fix sketch:** build an in-memory title→id index at load and resolve against it (index becomes accelerator-only); keep it sync for the styler.

---

### Out of scope — do not pursue (intended, refuted, parity, or platform-necessary)

- **JSON sidecars dropping unknown keys:** INTENDED, not a bug — see the model section. Sidecars are controlled schemas; preserve-everything is a markdown guarantee Swift already meets.
- **"Swift wipes foreign page frontmatter":** REFUTED for `.md` — the page path preserves foreign keys (only comments drop, Flag 1).
- **`IndexQuery` redundant `?? nil` swallowing a GRDB error:** already fixed in current code (a prior code-review removed it). Don't re-flag.
- **GRDB `String`/`SQLSpecificExpressible` overload workaround:** not present in Swift's `Index/`; that pattern bit the *React* side (`ContextPicker.tsx`), not here.
- **`SchemaTransaction` multi-file commit (~107 LOC):** PARITY — ported ~1:1 to React; both builds need it (no fs library covers multi-file atomic commit). Leave it.
- **Security-scoped bookmarks / `NSOpenPanel` retry / XCTest launch-modal guard (~150-200 LOC):** real but **platform-necessary** for a sandboxed Mac app. React avoids it only by being non-sandboxed Electron. Not a defect.
- **`@MainActor`/`Sendable`/`Codable`/DI ceremony at large** (the 20-property `NexusEnvironment` + its inject modifier, 114 `@MainActor`, etc.): real and verbose, but the cost of Swift 6 strict concurrency + SwiftUI — context for "why React is smaller," not an actionable fix.

### Recommended order

The clean DRY collapses first — **3, 4, 5, 6** (each deletes hundreds of duplicated lines with low behavioral risk). Then **2** and **8** (hardening / decoupling). Defer **1** (comments) and **7** (GRDB — architectural). The old "sidecar data-loss" headline is **closed as intended-design** — no action.
