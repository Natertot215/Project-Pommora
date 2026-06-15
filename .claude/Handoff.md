## Handoff — Pommora React

Lean current-state snapshot. Read first at session start.

### Session summary

The **headless data layer** is underway and building cleanly. After a 20-agent dual-research pass (Swift bloat × TS-native recreation; synthesis in `Planning/Data-Layer-Design.md`, load-bearing claims verified against real Swift — which caught + fixed a tier-shape doc bug in the Swift project's CLAUDE.md), shipped data-layer **Phases 0–3** as green commits: contracts + value codec + atomic I/O → page file engine (foreign-preserving) → sidecar schemas/kind/IO → folder + page CRUD. **130 tests; typecheck + build green.** Tests-only, zero UI wired (per directive). Earlier this session also landed the navigation spine (`80e210e`).

### Lessons learned

- Apple Liquid Glass over flat dark reads dark + edge-defined — never a brightened/white-tinted panel. Stop iterating a cosmetic detail when it blocks momentum; set it aside and build.
- `ELECTRON_RUN_AS_NODE=1` in this env breaks every GUI launch — strip it. Electron's ESM `require('electron')` fails → CommonJS main/preload.
- Greenfield multi-agent builds: keep stages **sequential + self-verified green** to stay coherent; parallel only for independent reads/reviews.

### Next session (continue the data layer)

1. **Finish Phase 3** — `crud/reorder.ts` (id-list reorder persisted to `state.json` via `mutateJson`) + wire `mutate:*` IPC handlers in `main/index.ts` + the preload bridge (renderer methods stay typed **stubs** — no UI). Test the handlers directly.
2. **Phase 4 — properties** — `properties/{schema,tiers}.ts`, `encodeValue` into page/agenda writes, per-property save + schema CRUD (schema-mutation atomicity via a `schemaTransaction`).
3. **Phase 5 — connections** (pure Map-based resolve + rename cascade), then **Phase 6 — SQLite index** (`better-sqlite3` behind `db.ts`).
4. **Deferred polish:** DRY-refactor `readNexus` onto `sidecarIO`/`kind`/schemas (net code removal) once singleton schemas land — verify against the read-engine tests.

Agenda CRUD folds into Phases 3–4 via an `agendaEntity` factory reusing `folderEntity` + `encodeValue`.

### Pending focuses

- **Glass:** Apple-Regular CSS is the working default; revisit `liquid-dom` only when HTML-in-Canvas ships unflagged. `Surface` is the swappable seam.
- **Window corner radius** (`--glass-radius`, currently 12px) — eyeball against the actual macOS window for concentricity (window radius − 5px inset).
- **Contexts in `~/test`:** the test nexus has no `.nexus/`/contexts, so the sidebar shows Vaults only. Add a couple of Areas/Topics/Projects to the fixture to exercise the Contexts section.
- **Glass Lab** at `glass-lab/index.html` (served via `python3 -m http.server 8765`) — 12-variant comparison page; keep for future glass tuning.

### Fix log

- Sidebar `resolveOrder` ignored its fallback param → adopted ids sorted by hash, not title. Fixed (title fallback for structure mode).
- Sandboxed ESM preload + `__dirname` in ESM main → switched to CommonJS; `sandbox: true` restored.
- Glass: removed `brightness()` + white fill (read too bright over flat dark) → edge-defined Apple-Regular recipe.
