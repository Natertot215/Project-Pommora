## Data Layer — Detailed Handoff

The complete continuation guide for Pommora's React data layer. Read this to pick up the work cold — what exists, where it lives, what it guarantees, what's deliberately not built, and exactly how to continue. The lean snapshot is `Handoff.md`; the per-phase retrospective + flag adjudication is `Data-Layer-Build-Log.md`; the forward spec is `Data-Layer-Design.md`. This doc is the bridge between them.

**Status:** Phases 0–7 shipped + a foundation review (review-certified). 220 vitest tests; typecheck + build green. Tests-only — **zero UI wired** (by directive). No catch-up scope and no open correctness flags remain. What's left is wiring the data layer to a UI.

---

### Orientation

- **Repo:** `/Users/nathantaichman/The Studio/Projects/Pommora - React` (branch `main`). Stack: Electron + React 19 + TypeScript, electron-vite, Vitest, Zustand. CommonJS main/preload (ESM `require('electron')` fails).
- **Swift source of truth:** `/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora` — the app being ported. When in doubt about behavior, read the Swift; every load-bearing claim here was verified against it.
- **Test nexus:** `~/test`. There is no production nexus here — adoption is intentionally minimal (`~/test` only).
- **The gate (every commit must pass):** `npm run typecheck && npm run build && npx vitest run`. All headless — no GUI.
- **Launching the GUI** (rare; a human looks): `env -u ELECTRON_RUN_AS_NODE TEST_NEXUS_PATH="$HOME/test" ./node_modules/.bin/electron .` after `npm run build`. `ELECTRON_RUN_AS_NODE=1` is set in this environment and breaks Electron — always strip it.
- **SLOC counter** (throwaway, used for the Swift↔React comparison): `/tmp/sloc.mjs` — `node /tmp/sloc.mjs <files…>`.

---

### Architecture & invariants (do not violate)

1. **Catch up to Swift, don't go ahead.** Only build what Swift shipped at the data level. No net-new subsystems. `blocks: []`, Homepage composition, and Settings-editing stay reserved/empty (Swift hasn't built them). "History" = Recents in `state.json`, not versioning.
2. **Files are canonical; byte-compatible on-disk format.** Same bytes as Swift, read/written natively in TS with no codec. Two additive wins only: foreign JSON keys (`z.looseObject`) and foreign-frontmatter comments (yaml Document API) now survive a rewrite.
3. **One process owns I/O.** All fs in the Electron **main** process. The renderer is sandboxed → narrow `contextBridge` → typed `ipcRenderer.invoke`. Every handler returns `{ ok: true, … } | { ok: false, error }` and never throws across the boundary. Reactivity = re-read the changed subtree after a mutation (no in-memory `@Observable` mirror).
4. **Every mutation returns `Result<T>`; never throws.** `ok(value)` / `fail(code, message, scope?)` from `shared/result.ts`. `code` is the closed `ErrorCode` union.
5. **DRY / one-file-owns-one-thing / simplicity-first / condensed control flow** (model finite states as enum + `switch`, not loose strings/booleans).
6. **Kind authority is path-based:** a folder's kind = which `_*.json` sidecar it carries; a `.md` file's kind = its parent folder's sidecar. Extension + frontmatter are non-authoritative.

#### On-disk format facts (load-bearing — verified against Swift)

- **`tier1`/`tier2`/`tier3` are BARE ULID string arrays at the frontmatter root** — NOT `$rel`-tagged. The `$rel` shape is only for user/agenda relation *properties* inside `properties`. (The reserved property-id form `_tier1/2/3` is a different string, used in `context_links.property_id` + the schema — see `tierFieldName` vs `tierPropertyId`.)
- **`PropertyValue` decode precedence is load-bearing + silent-on-failure** (`shared/propertyValue.ts`, mirrors `Vaults/PropertyValue.swift`): `null → bool → number → non-empty [{$rel}] → non-empty [FileRef] → [string] (incl. [] → multiSelect([])) → single {$rel}/{$status} → string(url → iso-datetime → yyyy-MM-dd → select) → throw`. Reordering a branch mistypes values with no error. ISO-datetime regex **rejects** fractional seconds (Swift's `.withInternetDateTime` does too — verified).
- **Index `context_links.target_kind` is the tier ENTITY kind** — `area` (tier 1) / `topic` (2) / `project` (3), per `RelationTargetKind.swift`. NOT `"context_tier"` (that's the relation_target config discriminant). This was a real bug caught in the foundation review.
- **`SCHEMA_VERSION = 14`** must equal Swift's `PommoraIndex.currentSchemaVersion`. The DDL is structurally identical to Swift's (`IndexSchema.swift` + the `meta` table) so either app can open + query the other's index; rows (e.g. synthesized link ids) need not be byte-identical (the index is regeneratable).

---

### Complete file map (data layer)

`src/shared/` — types + zod + codecs. Importable by main AND renderer; no fs, no React.

| File | Owns |
| --- | --- |
| `result.ts` | `Result<T>`, `PommoraError`, the closed `ErrorCode` union, `ok`/`fail`. |
| `propertyValue.ts` | The `PropertyValue` union + `parsePropertyValue`/`encodePropertyValue` (locked precedence) + `applyPropertyValue` (the set/clear owner) + `isPlainObject` (the shared shape guard) + `FileRef`. |
| `properties.ts` | `PropertyDefinition` zod model + `PropertyType` + reserved-ID catalog (`RESERVED_PROPERTY_ID`, `isReservedPropertyId`) + `tierFieldName`/`tierPropertyId`/`TIER_LEVELS` + `defaultStatusSeed` + lenient colors (`.catch`). |
| `schemas.ts` | zod sidecar schemas (pageType/collection/set/area/topic/project/agendaConfig) + `pageFrontmatter` + `PAGE_MODELED_KEYS`. `z.looseObject` everywhere (foreign keys ride). `property_definitions` stays a loose array — the per-def codec is `parseDefinitions`. |
| `agenda.ts` | `agendaTask`/`agendaEvent` zod models + `AGENDA_SUFFIX` + `agendaKindOf`/`agendaTitleOf`. |
| `connections.ts` | `normalizeTitle`, `pageLinkPattern` (the `[[…]]` regex), `LinkStatus`/`ScannedConnection`/`ConnectionEdge`/`LinkIndex`. |
| `types.ts` | The IPC/tree contract: `NexusTree` + node interfaces, `AREA_COLORS` (single source for the palette), view DTOs, IPC envelopes. |

`src/main/` — the Electron main process (fs lives here).

| File | Owns |
| --- | --- |
| `ids.ts` | `newId` (ulidx monotonic), `isUlid`, `adoptedId` (`adopted-<sha256>`), `mintPropertyId` (`prop_<ulid>`). The single identity owner. |
| `paths.ts` | The on-disk layout: `SIDECAR_FILENAME` (kind→file), `nexusDir`/`nexusConfig`/`contextTierDir`, `NEXUS_CONFIG_FILES`, `AGENDA_FOLDER_NAMES`. |
| `kind.ts` | `resolveKind(folder)` — stateless sidecar probe. |
| `coerce.ts` | `asString`/`asStringArray`/`basenameNoMd` (read-layer coercion). |
| `exclusion.ts`, `order.ts` | Folder-skip rules; `resolveOrder` (id-list ordering with id/title fallback). |
| `sidecarIO.ts` | `readSidecar`/`writeSidecar` (typed sidecar read/write through a zod schema). |
| `readNexus.ts` | The whole read walk → typed `NexusTree` (sidecar + raw-folder modes; lenient `splitFrontmatter`; roll-up; adopted ids; ordering). **Deliberately separate** from `sidecarIO`/schemas — it's the lenient *display* read, not the typed *write* contract. |
| `readPage.ts` | On-demand single-page read → `PageDetail`. |
| `index.ts` | The IPC host — read handlers (`nexus:open`, `page:open`), path-traversal-guarded. **Mutation handlers are NOT here yet** (deferred). |
| `io/atomicWrite.ts` | `atomicWriteFile`, `writeJson`/`serializeJson` (sorted, stable, trailing `\n`), `mutateJson`, `readJsonObject` (parse-a-JSON-file primitive), `pathExists` (the one existence check), `trashWithTimestamp`, `stableStringify`. |
| `io/pageFile.ts` | The page `.md` envelope: `splitEnvelope`/`assembleEnvelope` + `mergeFrontmatter` (set/delete only modeled keys via the yaml Document → foreign keys + comments preserved) + `writePageFile`. |
| `io/schemaTransaction.ts` | `SchemaTransaction` — two-phase multi-file commit (stage → rename-with-backup → rollback; sweeps only `.txn-`, keeps `.bak-` for recovery). For mutations touching the sidecar + member files together. |
| `io/walk.ts` | `listMarkdownFiles` (recursive, `skipTopLevel`), `listFilesBySuffix` (flat). |
| `crud/util.ts` | `pathExists` (re-export), `invalidName` (rejects separators, dot-dirs, `.md`/`.task.json`/`.event.json`), `nowIso`. |
| `crud/folderEntity.ts` | ONE create/rename/delete/`updateFolderSidecar` for all six folder entities (areas/topics/projects/types/collections/sets). |
| `crud/page.ts` | Page CRUD: create/rename/delete/move/`updatePageBody`/`updatePageProperty`/`setPageTier`. |
| `crud/agendaEntity.ts` | Agenda item CRUD (Tasks + Events): create/rename/delete/`updateAgendaItem`/`updateAgendaProperty`/`setAgendaTier`. |
| `crud/reorder.ts` | `setStateOrder` (state.json) + `setContainerOrder` (sidecar). |
| `crud/schema.ts` | Property-schema CRUD generalized over a `SchemaTarget` — `add`/`rename`/`reorder`/`delete`/`changeType` for Page Types AND agenda configs (page = frontmatter member-strip, agenda = JSON member-strip; delete + lossy changeType are atomic via `SchemaTransaction`). |
| `crud/cascade.ts` | `renameCascade` (rewrite inbound `[[links]]` nexus-wide) + `unlinkTier` (strip a deleted Context's id from member tier arrays). |
| `properties/schema.ts` | Pure transforms: `normalizeDefinition` (`.date`→`.datetime`, `relation_scope`→`relation_target`), `parseDefinitions` (per-def resilient), `droppingUserRelations`, `validateName`/`validateDefinition`. |
| `properties/tiers.ts` | `mergeTierProperties` — effective-schema synthesis (`BuiltInContextLinkProperties.merge` port). **NOT YET WIRED** (no consumer until the property-panel UI; the index builds tier links from raw arrays, not from this). |
| `connections/{scan,rewrite,resolve,edges}.ts` | Pure connection engine: scan body, rewrite titles, `buildLinkIndex` + `resolveTitle` (resolved/ambiguous/phantom), `connectionEdges`. No SQLite dependency. |
| `index/db.ts` | The `better-sqlite3` seam (`openDb` degrades to null; `transact`). Swap the driver here only. |
| `index/schema.ts` | The 11-table DDL + `SCHEMA_VERSION` + `applySchema`/`readSchemaVersion`/`stampSchemaVersion`. |
| `index/open.ts` | `openIndex` — version handshake (reuse / delete+recreate / `needsRebuild`). |
| `index/upsert.ts` | Per-entity `INSERT OR REPLACE` (generic core + typed wrappers) + `replaceContextLinks`/`replaceConnections` (delete-by-source reconcile). |
| `index/build.ts` | `buildIndex` (collect-then-transact cold build) + `rebuildIndex` (open → build-if-needed → stamp). Populates every table from the files. |

#### Single-owner primitives — REUSE these, don't re-create

The DRY pass concentrated repeated logic into these. A continuer should call them, not re-implement:

- Shape guard → `isPlainObject` (`shared/propertyValue.ts`).
- Property set/clear → `applyPropertyValue` (`shared/propertyValue.ts`).
- JSON file → record → `readJsonObject` (`io/atomicWrite.ts`).
- Existence check → `pathExists` (`io/atomicWrite.ts`, re-exported from `crud/util.ts`).
- Read coercion → `coerce.ts`.
- Tier strings → `tierFieldName(n)` = `tierN` (root field), `tierPropertyId(n)` = `_tierN` (reserved id), `TIER_LEVELS` (`shared/properties.ts`).
- Name validity → `invalidName` (`crud/util.ts`).
- Atomic single-file write → `atomicWriteFile`/`writeJson`; multi-file → `SchemaTransaction`.
- Page frontmatter write (foreign-preserving) → `mergeFrontmatter`/`writePageFile`.

---

### Swift fidelity map (for future verification)

| React | Swift |
| --- | --- |
| `propertyValue.ts` | `Vaults/PropertyValue.swift` |
| `properties.ts` | `Vaults/PropertyDefinition.swift` + `PropertyType.swift` + `ReservedPropertyID.swift` + `Vaults/BuiltInContextLinkProperties.swift` |
| `crud/schema.ts` | `Properties/PerTypeSchemaService.swift` + `SingletonSchemaService.swift` + `Vaults/MemberFileStrip.swift` |
| `io/schemaTransaction.ts` | `AtomicIO/SchemaTransaction.swift` |
| `io/pageFile.ts` | `AtomicIO/AtomicYAMLMarkdown.swift` + `Content/PageFile.swift` |
| `connections/*` + `crud/cascade.ts` | `Connections/{ConnectionScanner,ConnectionResolver,ConnectionCascade,ConnectionTitle}.swift` |
| `agenda.ts` + `crud/agendaEntity.ts` | `Agenda/{AgendaTask,AgendaEvent,Recurrence}.swift` + the two managers |
| `index/*` | `Index/{IndexSchema,IndexBuilder,IndexUpdater,PommoraIndex,RelationTargetKind}.swift` (the rich `IndexQuery` is NOT ported) |
| `readNexus.ts` | the read/load logic spread across Swift's per-entity managers |

---

### What is NOT built (and why)

#### Deferred until UI (the no-routing directive — building now is premature)

1. **`mutate:*` / `index:*` IPC handlers + the preload bridge.** The renderer methods are typed stubs. The CRUD/index functions exist and are tested in isolation but **nothing calls them yet**.
2. **Incremental index upserts.** `rebuildIndex` cold-builds; the index does NOT auto-update after a mutation. Wire the best-effort upserts (swallowed) into each IPC handler when it lands. Also needs `electron-rebuild` + `asarUnpack` so the Electron main process can load `better-sqlite3` in a packaged build (for vitest under Node it already works via the prebuilt binary), and the `loadAll-sync-parents` defensive upsert.
3. **Cascade orchestration.** `renameCascade`/`unlinkTier` exist standalone. The orchestration — renamePage → renameCascade with **revert-the-rename-on-throw**, and Context-delete → unlinkTier **before** removing the context folder — is the data-layer policy that belongs at the mutation/IPC layer. It is the load-bearing part of Swift's design; don't let each call site re-invent it.

#### Deferred with a specific reason (see Build-Log § Foundation Review)

- **`build.ts` re-reads container sidecars** `readNexus` already parsed. Do NOT "fix" this by putting sidecar fields (esp. `property_definitions`) on the display nodes — that bloats the renderer's IPC payload with data the sidebar never uses. The clean fix is a side-channel read (`readNexus({ collectSidecars })`) returning the raw sidecars separately; do it when the index is wired. Cold-path-only (rebuild).
- **The connection engine isn't on the read path.** `buildLinkIndex`/`connectionEdges` exist but `readNexus` doesn't yet collect `linkIndex.byTitle` + `contextsById`. Wire it when a consumer (backlinks panel / inline link styling) exists.

#### Refuted (do not do)

- **"Refactor `readNexus` onto `sidecarIO`/schemas."** This would couple the lenient display read to the typed write contract (forcing the read engine to import every entity schema) — a regression, not a cleanup. The real duplication there (micro-helpers) is already deduped. The typed (`sidecarIO`) and lenient (`readNexus`) read paths stay separate by design.

#### Out of scope (Swift hasn't shipped, or platform-specific)

`blocks: []` editing (Homepage + contexts), Homepage composition, Settings-editing UI (storage + read are built); EventKit calendar sync (agenda `calendar_id`/`eventkit_uuid` round-trip but nothing mirrors to the system calendar); attachment file-copy; the full adoption flow; file-version history; a filesystem watcher; the view query surface (`IndexQuery`) + view pipeline (filter/sort/group) + Table/Gallery renderers + the page editor (CodeMirror/react-markdown) — those are separate post-data-layer phases.

---

### How to continue — the next phase (UI + IPC wiring)

The data layer is a set of tested modules waiting to be called. The next real work is the renderer + the wiring between them. The seating pattern (from `Data-Layer-Design.md`):

```
renderer → preload.nexus.<verb>(args) → ipcRenderer.invoke('mutate:<verb>')
        → main handler (validate + resolve path under session.rootPath, the existing traversal guard)
        → crud/* (→ io/* + properties/* + schemas)
        → best-effort index upsert (swallowed)   ← wire incremental index here
        → return { ok, … }
        → renderer re-reads the changed subtree
```

Concrete first steps, in order:
1. **Add the mutation IPC handlers** in `src/main/index.ts`, one per CRUD verb (createEntity / renameEntity / movePage / deletePage / updatePageBody / updatePageProperty / setPageTier / reorder / the agenda + schema verbs). Each validates, resolves the path under the session root (reuse the existing `page:open` traversal guard), calls the `crud/*` function, returns its `Result`. Test each handler directly (call it, assert the envelope + the on-disk result) — the established headless pattern.
2. **Extend the preload bridge** (`src/preload/index.ts`) with the narrow typed methods. No fs leaks.
3. **Wire incremental index upserts** into each handler (after the crud call, best-effort, swallow failures) using `index/upsert.ts`. Add the `electron-rebuild` + `asarUnpack` build step so main can load `better-sqlite3` packaged.
4. **Add the cascade orchestration** as a thin wrapper (e.g. `renamePageWithCascade`) so the revert-on-throw invariant has one home.
5. **Build the UI** from the Figma Component Library, calling the bridge; reactivity = re-read after each mutation.

When you touch the index wiring, that's the moment to also do the two deferred-with-reason items (the side-channel sidecar read; the connection engine on the read path).

---

### Testing, gotchas, lessons

- **33 test files, 220 tests**, co-located `*.test.ts`. Each module + the cold build is covered; the build test (`index/build.test.ts`) exercises the whole stack end-to-end (folder + schema + page CRUD → readNexus → connection engine → index).
- **Verify findings against source — including your own.** The foundation review's headline critical (`target_kind`) flipped a conclusion *I* had written, and a review agent's "Swift accepts fractional seconds" was wrong on inspection. A green suite proves consistency, not correctness. Read the Swift.
- `readNexus` and `pageFile` both use the **`yaml` package** (not js-yaml) — no cross-parser risk.
- `mutateJson` is read-modify-write, **not** transactional — safe only if same-file writes are serialized (do it at the IPC layer; Swift relied on `@MainActor`).
- Commit messages: use `git commit -F -` with a heredoc — backticks in a `-m "…"` double-quoted string get shell-interpreted and mangle the message.

---

### Key commits

Build: `d523dcc` (P0) · `c0ba4df` (P1) · `8f71db9` (P2) · `18cda71`/`d55dc5a`/`6ae13c7` (P3) · `ab43e49`…`b3193e6` (P4) · `de0a878`…`5c63484` (P5) · `f54f869`…`7a85c4a` (P6) · `0f87383`…`5caf60b` (P7).
Foundation review: `d712999` (atomicity) · `8309e20` (target_kind + self-link) · `4f15ba8` (colors/ErrorCode/name/AreaColor) · `f3737b0`/`aa2a1d1`/`e8f8364` (DRY) · `ab34707` (docs).

**Swift → React data-layer LOC: 8,552 → 2,383 SLOC (~72%, shared-functionality-only).** The −92% on CRUD managers (the `folderEntity` + `SchemaTarget` factory consolidation) is the bulk; connections is the one area React is slightly larger (pure-Map resolve vs Swift's SQLite-backed).
