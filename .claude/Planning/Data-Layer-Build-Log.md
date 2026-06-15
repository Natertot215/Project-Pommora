## Data Layer — Build Log

A per-phase record of what was built, why, how it departs from the Swift implementation and why, and **⚐ review flags** — uncertainties left deliberately for a later code-review + simplification pass (each flag is a *where* + a *why*). Forward spec lives in `Data-Layer-Design.md`; this is the retrospective. Appended as each phase ships.

Convention: everything is headless (tests-only, no UI wired); every commit is green (typecheck + build + vitest).

### Phase 0 — contracts, ID owner, value codec, atomic I/O · `d523dcc`

**What.** `shared/result.ts` (`Result`/`PommoraError` + `ok`/`err`/`fail`); `shared/propertyValue.ts` (the `PropertyValue` union + `parse`/`encode`); `main/ids.ts` (`newId` via ulidx monotonic, `isUlid`, `adoptedId`); `main/io/atomicWrite.ts` (`atomicWriteFile`, `writeJson`, `mutateJson`, `stableStringify`, later `trashWithTimestamp`).

**Why.** Everything downstream needs a never-throw result type, a safe-write primitive, identity, and the value codec. Built first, in isolation, because they're pure and the codec is the single highest-risk module.

**Swift delta + why.** The `PropertyValue` codec is a ~60-line pure function pair instead of Swift's ~117-line custom `Codable` with shape-sniffing `init(from:)`/`encode(to:)` — same precedence, no `Codable` ceremony, no `any Decoder`. `adoptedId` is now one owner; Swift (and our own early read engine) had the sha256 logic duplicated. Atomic write is the *default* path, not a special helper.

**⚐ Review flags.**
- `propertyValue.ts` date check is **format-only** (`/^\d{4}-\d{2}-\d{2}$/`): `"2026-13-45"` classifies as `date`, where Swift's `DateFormatter` rejects it → `select`. Round-trip is byte-stable either way (both re-emit the string), so impact is the in-memory `.kind` only. *Decide whether real date validation is worth it; schema is the type authority anyway.*
- `propertyValue.ts` URL test is a scheme regex, not Swift's permissive `URL(string:)`. Close, but edge strings (`"Note:x"` → url) may differ. Same byte-stability caveat.
- `parsePropertyValue` **throws** on an unrecognised shape (matches Swift) — but the design ethos elsewhere is "lenient by default." *Confirm throw vs. returning `{kind:'null'}`.*
- `result.ts` ships `ok`, `err`, **and** `fail`. CRUD uses `ok`/`fail`; `err` may be unused → **simplification candidate** (drop `err` or justify it).
- `mutateJson` is read-modify-write but **not transactional**: two concurrent `mutateJson` calls on the *same* file can interleave (read A, read B, write A, write B → A lost). Safe only if same-file writes are serialized. *Flag for a per-file write queue if concurrent same-file mutation becomes real.*
- `FileRef` uses snake_case keys (on-disk DTO) — unusual in TS. Intentional (round-trips as-is); confirm acceptable.

### Phase 1 — page file engine · `c0ba4df`

**What.** `main/io/pageFile.ts`: `splitEnvelope`/`assembleEnvelope` (the `---\nfm---\n\nbody` contract) + `mergeFrontmatter` (parse original frontmatter to a yaml Document, `set`/`delete` only modeled keys, reassemble) + `writePageFile`.

**Why.** The write counterpart to the existing `readPage`. The foreign-preservation guarantee is the load-bearing correctness property of the whole layer.

**Swift delta + why.** Swift's lossy typed `Codable` round-trip forced a hand-rolled ~70-line Yams `Node` merge to retain foreign keys, and it still dropped comments. The yaml Document API retains foreign keys **and comments** natively because we never reconstruct the object — we touch only modeled keys on the parsed original. Net: less code, strictly more preserved.

**⚐ Review flags.**
- **First-write styling may not be byte-identical to Swift/Yams** (flow vs block, quoting) on a freshly-set modeled key. Accepted by design (value + envelope-frame equality, not serializer quoting; re-save is idempotent). *Reviewer: confirm the reflow tolerance is acceptable, and that no consumer depends on exact Swift bytes.*
- `mergeFrontmatter`'s contract — *set if in `modeled`, else delete (for keys in `modeledKeys`)* — is a **footgun**: a caller that lists a key in `modeledKeys` but omits its value silently deletes it. Works because callers pass a deliberate governed set (full set for create, `['modified_at']` for body update). *Consider a safer API (explicit `{set, clear}`) or a guard.*
- Corrupt non-map frontmatter is **silently discarded** (`doc = parseDocument('')`). Acceptable (it can't be page frontmatter), but it's silent data loss. *Confirm.*
- `splitEnvelope` strips exactly one separator blank line; extra leading blank lines stay in the body. *Confirm this matches Swift's body semantics.*

### Phase 2 — sidecar schemas, kind authority, sidecar I/O · `8f71db9`

**What.** `shared/schemas.ts` (zod v4: `baseSidecar`/`contextBase` builders → pageType/collection/set/area/topic/project + `pageFrontmatter` + `PAGE_MODELED_KEYS`); `main/kind.ts` (`resolveKind`); `main/sidecarIO.ts` (`readSidecar`/`writeSidecar`).

**Why.** The codec/type/validation layer CRUD writes through, and the path-based kind authority CRUD and the reader rely on.

**Swift delta + why.** One zod schema is simultaneously validator, on-disk format, and static type (`z.infer`) — replacing Swift's separate struct + custom `Codable` + `CodingKeys` (which drift; that drift caused the tier-shape doc bug). `z.looseObject` retains foreign keys on **all** JSON sidecars, closing Swift's silent-drop data-loss gap. Shared builders collapse Swift's three byte-identical context managers. Kind authority is a stateless fs probe, not an `@Observable` singleton in an injection graph that could SIGTRAP.

**⚐ Review flags.**
- **Schema coverage is partial:** folder + context sidecars + page frontmatter only. The `.nexus/*` **singletons** (settings/state/nexus/saved-config/sidebar-sections/tier-config/homepage) are **not modeled yet**, and `readNexus` still reads them with its own untyped `readJson`. *This is the readNexus-DRY-refactor debt — two ways to read sidecars coexist until singletons land.*
- Area `color` is `z.string().optional()`, **not** the 10-case `AreaColor` enum — lenient (an unknown color survives rather than failing the whole sidecar). *Decide: validate against the enum (with `.catch`) or keep lenient + coerce at read.*
- `property_definitions` is an unmodeled `z.array(z.looseObject({}))` placeholder until Phase 4.
- `resolveKind` returns the **first** matching sidecar; a folder carrying two sidecars (shouldn't happen) is silently disambiguated by iteration order, and it does up to 8 `stat`s per folder. *Reviewer: detect-ambiguity? read the dir once instead?*
- `readSidecar` returns `null` on validation failure (e.g. missing `id`) — discarding any foreign data on a malformed sidecar. Swift was more lenient. *Confirm null-on-invalid isn't too lossy.*

### Phase 3 — CRUD lifecycle · `18cda71` folder · `d55dc5a` page · reorder (this commit)

**What.** `crud/folderEntity.ts` (one `create`/`rename`/`delete`/`updateSidecar` for all six folder entities) + `crud/page.ts` (`create`/`rename`/`delete`/`updatePageBody`/`move`) + `crud/reorder.ts` (`setStateOrder` → state.json for vaults/tiers; `setContainerOrder` → sidecar for collections/sets/pages). `trashWithTimestamp` added to `atomicWrite.ts`. The operation set is now complete: create/rename/delete/update/move/reorder.

**Why.** The actual mutation capability — the spine of the app. The folder factory is the big DRY win (Swift copy-pasted these ladders across managers).

**Swift delta + why.** One generic factory replaces per-entity managers + their copy-pasted rollback ladders. No `@MainActor`/`Sendable`/DI — plain async functions. No security-scoped bookmarks. Delete = in-nexus `.trash` (recoverable, files canonical) rather than OS trash. Errors flow as `Result`, never thrown.

**⚐ Review flags.**
- `createFolderEntity` writes `{id, ...extra}` **without schema-validating** the result — it trusts the caller's `extra`. A wrong field shape writes a malformed sidecar (caught only on next read). *Validate-on-write against the kind's schema?* (Needs a kind→schema map — couples the factory to schemas; weigh against DRY.)
- **No `validators.ts` yet.** Name-collision is inline; the design's richer validators (page title shape, tier-target existence, property-type match) are unbuilt. *Phase 3/4 debt.*
- `updateFolderSidecar` merges `patch` over current but **doesn't re-validate** the merged object.
- `movePage` does **not** strip cross-type properties (a page moved to a type with a different schema keeps stale property keys). Deferred to Phase 4 (needs the schema-aware property layer). *Known gap.*
- Name safety is minimal: rejects `/`, `\`, `.`/`..`, blank. It does **not** strip a trailing `.md` (title `"Note.md"` → file `Note.md.md`), nor guard OS-illegal chars (`:`), trailing spaces, or reserved names. *Reviewer: harden name validation centrally (a shared `validateName`).*
- `crud/folderEntity.ts` and `crud/page.ts` each re-implement `exists`, `invalidName`, `nowIso`. **Small DRY duplication** — candidate to hoist into a shared crud util.
- `reorder.ts` persists whatever id list it's given — it does **not** validate the ids exist. Harmless on read (`resolveOrder` ignores unknown ids), but a garbage/stale id silently lands in the order array. *Confirm no existence check is needed, or add one.*

### Phase 4 — properties (value write + schema CRUD)

#### 4a — property value write · `ab43e49`

**What.** `crud/page.ts` `updatePageProperty(absFile, propertyId, value | null)`: set/clear one property value, encoded via the Phase-0 codec; governs only `properties` + `modified_at`, so sibling properties and all other frontmatter survive; null/`null`-kind removes the key.

**Why.** Wires the value codec into the write path — the core of "properties are editable." (Property-schema CRUD on the type sidecar + tier synthesis are the next Phase-4 increments.)

**Swift delta + why.** Swift ran every value through the `PropertyValue` `Codable` on each save; here one `encodePropertyValue` emits the on-disk shape and the Document merge preserves the rest of the page untouched — the codec is the only property-specific code on the write path.

**⚐ Review flags.**
- **"Omit empty" is partial:** a null/`null`-kind value deletes the key, but an empty array (e.g. `multiSelect []`) writes `[]`. The design says user relations omit when empty. *Decide whether empty arrays should also delete the key.*
- `updatePageProperty` parses the frontmatter **twice** (`splitFrontmatter` to read current props, `mergeFrontmatter` to write). Minor; could read the Document once.
- **No schema awareness yet:** it writes any `propertyId` with any value-kind without checking the type's `property_definitions` (wrong-type value or unknown property id is accepted). 4b builds the schema side but the value-write path is still not cross-checked against it.

#### 4b — property-schema CRUD + tier synthesis · `df91fb1` util · `18c0b69` model · `681dc97` transforms · `1bdd555` txn · `b3193e6` schema CRUD

**What.** The schema (definition) side, in dependency order. `crud/util.ts` (hoisted `pathExists`/`invalidName`/`nowIso`; folderEntity + page refactored onto it). `shared/properties.ts` (the `PropertyDefinition` zod model + `PropertyType` + reserved-ID catalog + `defaultStatusSeed`; `mintPropertyId` added to `ids.ts`). `properties/schema.ts` (pure `normalizeDefinition` + `parseDefinitions` + `droppingUserRelations` + `validate{Name,Definition}`). `properties/tiers.ts` (`mergeTierProperties` — `_tier1/2/3` synthesis). `io/schemaTransaction.ts` (atomic multi-file commit). `crud/schema.ts` (the five ops: add/rename/reorder = sidecar-only; delete + lossy `changeType` = sidecar + member-strip via the transaction).

**Why.** Completes "properties are editable" — value write (4a) + schema write (4b). The transaction is the one new primitive: a delete / lossy-retype must rewrite the type sidecar **and** strip the property from every member page together-or-not-at-all.

**Swift delta + why.** ~1,400 Swift lines (PropertyDefinition 334 + PerTypeSchemaService 353 incl. its 96-line adapter protocol + the duplicate SingletonSchemaService 334 + SchemaTransaction 153 + validator 44 + ReservedPropertyID 79 + BuiltInContextLinkProperties 65 + MemberFileStrip 40) collapse to ~620 TS lines. Gone: the `PerTypeSchemaAdapter` DI protocol (built for the @MainActor manager), the duplicated singleton service (one parameterized path here), the index-on-write upserts (Phase 6), the `pendingError` toast sink, and the ~117-line PropertyDefinition Codable. The model is one zod schema; the five ops are plain async functions returning `Result`. Resilience is parity (Swift is per-def tolerant via `try?`; here it's `parseDefinitions` per-element) but simpler. A design refinement landed mid-phase (the "re-assess between green commits" rule): `pageTypeSidecar.property_definitions` stays a **loose array** (one bad def can't sink the type) with `parseDefinitions` as the per-def codec, rather than `z.array(propertyDefinition)` (all-or-nothing) wired in 4b-i.

**⚐ Review flags.**
- `shared/properties.ts`: `selectColor` / `statusGroupId` are **strict** zod enums inside a def — an unknown color in `select_options`/`status_groups` fails the def parse, so `parseDefinitions` **drops the whole def** (resilient skip). Lossier than Area `color` (lenient string, Phase-2 flag). *Decide: `.catch()` the color enum to match the lenient ethos.*
- `shared/properties.ts`: pure display config (`number_format`, `date_format`, `time_format`, `display_as`, `date_includes_time`) is **not modeled** — rides as foreign keys (round-trips, unvalidated) until a UI reads it. Intentional (catch-up). *Confirm.*
- `properties/schema.ts`: `parseDefinitions` **silently drops** an unparseable def; `normalizeDefinition` rewrites `.date`→`.datetime` + folds `relation_scope` on every def, so any schema op **persists** that migration on next write. Faithful to Swift, but both are silent data-shape effects. *Confirm.*
- `properties/schema.ts`: rename validates name-uniqueness only (not the renamed def's select-option rules, unlike Swift's `validate(renamedDef…)`). Equivalent for already-valid defs. *Confirm the narrowing.*
- `properties/tiers.ts`: the `tierPlural` resolver isn't wired to `tier-config.json` (singleton unmodeled) → tier names are always "Tier N" until singletons land. *Phase debt, not a bug.*
- `io/schemaTransaction.ts`: the **phase-2 (rename) rollback** path isn't directly unit-tested — no portable way to force a mid-commit rename failure; covered by reading + the symmetric stage-failure test. Rollback is best-effort (no fs transaction); a crash mid-commit relies on the next commit's stale sweep (same surface as Swift). *Confirm acceptable.*
- `crud/schema.ts`: member strip **bumps each stripped page's `modified_at`** (the page changed). *Confirm parity with Swift's strip.*
- `crud/schema.ts`: `readSidecar` still returns null if the **whole** sidecar is structurally invalid (a corrupt non-def field blocks every schema op), even though `property_definitions` is now per-def resilient. Same Phase-2 readSidecar-lossiness flag.
- `crud/schema.ts`: **no agenda config-schema CRUD** (`_taskconfig`/`_eventconfig`) yet — folds in via the agendaEntity factory (reuses these transforms + a JSON member strip). **No index upsert** on schema mutation (Phase 6).

### Phase 5 — connections & tier relations · `de0a878` scan/rewrite · `1fc2488` resolve/edges · `fa6877c` walk + setPageTier · `5c63484` cascades

**What.** The connection system + tier-relation writes + cascades, pure-first. `shared/connections.ts` (`normalizeTitle`, `pageLinkPattern`, the `LinkStatus`/`ScannedConnection`/`ConnectionEdge`/`LinkIndex` types). `connections/scan.ts` + `connections/rewrite.ts` (pure body ops). `connections/resolve.ts` (`buildLinkIndex` + `resolveTitle`) + `connections/edges.ts` (`connectionEdges`). `io/walk.ts` (`listMarkdownFiles`; schema.ts's inline walk refactored onto it). `crud/page.ts` `setPageTier` (tier-N root array write). `crud/cascade.ts` (`renameCascade` rewrites inbound `[[links]]`; `unlinkTier` strips a deleted Context's id from tier arrays) — both atomic via `SchemaTransaction`.

**Why.** Connections are the page→page link graph; tier relations connect pages to Contexts. Catch-up to Swift, which has scanner/resolver/rewriter/cascade/unlinkTier.

**Swift delta + why.** Swift resolves connections + finds inbound edges via **SQLite** (`IndexQuery.incomingConnections` / `incomingContextLinks`) and resolves synchronously inside the TextKit layout pass. React's engine is **pure Map** — `buildLinkIndex` + `resolveTitle` over an in-memory index, and the cascades find the inbound set by **scanning** page bodies. So connection correctness has **no SQLite dependency**: Phase 6's index becomes a pure accelerator (narrow the inbound walk), not a load-bearing layer. ~940 Swift connection LOC (incl. the autocomplete/TextKit/bus pieces, which are UI and not ported) → ~150 TS for the headless engine + cascades. The TextKit-coupled `PommoraConnectionResolver` (a `WikiLinkResolver` for inline styling) is UI — out of scope here.

**⚐ Review flags.**
- **The pure engine is built but not yet wired into the read path.** The design's "extend the `readNexus` walk to collect `linkIndex.byTitle` + `contextsById`" is **not done** — `resolve`/`edges` are tested with hand-built indexes; nothing builds the nexus-wide index at read time yet. Deferred deliberately (no consumer until UI; Phase 6's index may serve it). *Wire when a consumer exists.*
- `crud/cascade.ts`: both cascades **walk every page** (O(all pages)) to find the inbound set — no index. Fine for `~/test`; Phase 6 can narrow it. *Perf flag.*
- `crud/cascade.ts`: `renameCascade` is **body-only** and reserializes inbound frontmatter via the yaml Document — value-preserving but may **normalize non-canonical YAML styling** on touched pages (the Phase-1 first-write-styling flag, now on cascade-touched pages). `modified_at` deliberately **not** bumped (Swift parity for a derived edit). *Confirm both.*
- `crud/cascade.ts`: cascades are **standalone** — orchestration (renamePage → renameCascade with revert-on-throw; Context delete → unlinkTier before removing the folder) is the mutation/IPC layer's job (deferred, no UI). *Not wired.*
- `setPageTier` / cascade: tier ids + connection targets are **not existence-checked** (a stale/garbage id is stored/kept) — same as reorder's no-validation flag.
- `shared/connections.ts`: `normalizeTitle` uses JS `trim()`+`toLowerCase()` vs Swift `.whitespacesAndNewlines`+`.lowercased()` — equivalent for ASCII; exotic-Unicode case-folding may differ marginally. *Confirm acceptable.*
- `connections/resolve.ts`: a page that links its own title resolves to **itself** (self-edge) — not filtered. *Confirm benign.*

### Phase 6 — SQLite index · `f54f869` seam+schema · `d99d89f` open · `2f4b49f` upsert · `7a85c4a` build

**What.** The regeneratable index accelerator, behind `db.ts`. `index/db.ts` (better-sqlite3 seam: `openDb` degrades to null → file-only reads; `transact`). `index/schema.ts` (the 10 entity tables copied byte-compatibly from Swift's `IndexSchema` + the `meta` table + 14 indexes; `SCHEMA_VERSION=14`). `index/open.ts` (`openIndex` — version handshake: reuse at current version, else delete DB+WAL/SHM and recreate; `needsRebuild`). `index/upsert.ts` (generic INSERT OR REPLACE + typed wrappers; replace-by-source for connections + context_links). `index/build.ts` (`buildIndex` collect-then-transact; `rebuildIndex` open→build→stamp-on-success).

**Why.** Cross-cutting queries (filter/sort/group by property, by tier, the connection graph) that a file walk can't answer cheaply. Off the read path: `readNexus`/`readPage` stay the only content path; a failed index degrades to files.

**Swift delta + why.** GRDB + its `*Snapshot` mirror structs + the `String`-overload workarounds + the two-phase MainActor index walk collapse to hand-written parametrized SQL behind one sync driver. The DDL is **byte-compatible** (ids match the sidecars), so a Swift- and a React-built `index.db` are interchangeable. The defining win is positional, not LOC: because Phase-5 resolution is pure-Map, the index is a **pure accelerator** here — Swift *needs* it for connection resolution; React doesn't. better-sqlite3 installed from a **prebuilt binary** (no native compile; `electron-rebuild`/`asarUnpack` only matter once main loads it in a packaged build — deferred with the no-UI wiring). ~1,742 Swift index LOC → ~430 TS.

**⚐ Review flags.**
- **Not wired to anything.** `rebuildIndex` exists but nothing calls it, and incremental upserts are **not** wired into CRUD (the integration point is the IPC handler, deferred until UI). So after a mutation the index is stale until the next `rebuildIndex`. The biggest deferred item — with `electron-rebuild`/`asarUnpack` (packaging) + the `loadAll-sync-parents` incremental path. *Wire at the IPC layer when UI lands.*
- `index/build.ts` **re-reads** type/collection/set sidecars that `readNexus` already parsed (folder paths reconstructed from titles). Folds into the readNexus refactor (expose `modified_at`/`schema_version`/`property_definitions` on nodes). *Perf + DRY.*
- `index/build.ts` synthesizes **deterministic** ids for `context_links` (`<pageId>:_tierN:<ctxId>`) + `connections` (`<pageId>:<normalizedTitle>`) — differ from Swift's (likely ULIDs), but link-row ids are internal to the regeneratable index; interchange rides on the entity ids (page/context/title). *Confirm interchange unaffected.*
- `index/build.ts` indexes `parseDefinitions(...)` as stored (incl. a reserved `_tierN` override entry if present) **without** `droppingUserRelations`. *Confirm parity with Swift's IndexBuilder (whether a retired user-relation def should be excluded from the index like the runtime schema).*
- Container `modified_at` falls back to EPOCH when the sidecar lacks it; page `modified_at` → `created_at` → EPOCH. *Confirm acceptable (regeneratable; rarely the container sort key).*
- `agenda_tasks` / `agenda_events` tables exist but the build **doesn't populate** them (no agenda CRUD yet) — folds in with agenda.
- `index/db.ts` sets WAL + `foreign_keys=ON` per connection (build inserts in FK-safe order). 3 npm-audit high advisories are in `prebuild-install` (dev tooling, not shipped runtime).

### Phase 7 — Agenda CRUD · `0f87383` items · `db47125` index pop · `5caf60b` config-schema CRUD

**What.** The last data-layer subsystem. `shared/agenda.ts` (agendaTask/agendaEvent zod models + suffix/kind helpers). `crud/agendaEntity.ts` (one factory for both kinds: create/rename/delete/updateItem/updateProperty/setTier). Index pop: `upsertAgendaTask`/`upsertAgendaEvent` + `collectAgenda` in `build.ts` (discovers agenda folders by sidecar, indexes items + tier links + config defs). Agenda config-schema CRUD by **generalizing `crud/schema.ts`** over a `SchemaTarget` (page vs agenda) — one five-op core, page exports unchanged, new `addAgendaProperty`/etc. with a JSON member strip. Config folders reuse `createFolderEntity` (kind `taskConfig`/`eventConfig`).

**Why.** Swift ships Tasks (EKReminder) + Events (EKEvent) at the data level; catch-up requires them. The generalization is the DRY payoff: Swift's `PerTypeSchemaService` + `SingletonSchemaService` (≈690 LOC, near-duplicate) become one parameterized path.

**Swift delta + why.** Agenda items are pure JSON (no envelope), so the factory is simpler than `page.ts` — read-merge-write with raw-spread foreign preservation, no Yams/Document. The ~117-line `PropertyValue` Codable + the per-manager `addProperty`/`changeType`/`unlinkTier` ladders across `AgendaTaskManager` + `AgendaEventManager` (≈660 LOC) collapse into the shared codec + the generalized schema ops + the existing `unlinkTier`. ~1,000 Swift agenda LOC (models + 2 managers + 2 schemas, excl. EventKit-sync + UI) → ~260 TS.

**⚐ Review flags.**
- `crud/agendaEntity.ts`: `createAgendaItem` requires an event's `start_at` + `end_at` but does **not** enforce `end_at ≥ start_at` (Swift's invariant). *Decide whether to validate.*
- Dates are opaque ISO **strings** (round-tripped, not validated) — an invalid date string survives. Schema is lenient; EventKit sync / UI would validate. *Confirm.*
- `updateAgendaItem` is an **additive merge** (no field-deletion semantics, unlike page `mergeFrontmatter`'s set-or-delete); field removal is only via `updateAgendaProperty`. *Confirm sufficient for the field set.*
- Recurrence + EventKit fields (alarms, `calendar_id`, `eventkit_uuid`) ride **loosely** (round-tripped, not deeply modeled) — catch-up; deep recurrence editing is a UI concern.
- `writeJson` sorts keys, so a Swift-written agenda file re-saved in React **reorders keys** (cosmetic, data-identical) — same first-write-styling flag as pages.
- `collectAgenda` scans the **nexus root only** for agenda folders (Swift's default Tasks/Events live at root); a nested agenda folder wouldn't be indexed. *Confirm root-only is the model.*
- Reconciled while wiring agenda: tier `context_links.target_kind` was `'context'`. **(Foundation-review correction:** it is now `'area'`/`'topic'`/`'project'` per tier — matching Swift's `RelationTargetKind.string(from: .contextTier(n))`. An intermediate `'context_tier'` value was wrong — that string is the relation_target *config* discriminant, not this column.)
