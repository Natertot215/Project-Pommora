## Handoff — Pommora React

Lean current-state snapshot. Read first at session start.

### Session summary

The **headless data layer** is built through Phase 6. After a 20-agent dual-research pass (Swift bloat × TS-native recreation; synthesis in `Planning/Data-Layer-Design.md`, load-bearing claims verified against real Swift — which caught + fixed a tier-shape doc bug in the Swift project's CLAUDE.md), shipped data-layer **Phases 0–6** as green commits: contracts + value codec + atomic I/O → page file engine (foreign-preserving) → sidecar schemas/kind/IO → folder + page CRUD + reorder → properties (value + schema CRUD + tier synthesis + SchemaTransaction) → connections & tier relations (pure-Map engine + renameCascade + unlinkTier + setPageTier) → **SQLite index (better-sqlite3 behind db.ts; byte-compatible 11-table schema + version handshake + per-entity upserts + cold build)**. **209 tests; typecheck + build green.** Tests-only, zero UI wired (per directive). Earlier this session also landed the navigation spine (`80e210e`). Per-phase record + all ⚐ review flags in `Planning/Data-Layer-Build-Log.md`. **Remaining catch-up:** Agenda CRUD (the last data-layer subsystem).

### Lessons learned

- Apple Liquid Glass over flat dark reads dark + edge-defined — never a brightened/white-tinted panel. Stop iterating a cosmetic detail when it blocks momentum; set it aside and build.
- `ELECTRON_RUN_AS_NODE=1` in this env breaks every GUI launch — strip it. Electron's ESM `require('electron')` fails → CommonJS main/preload.
- Greenfield multi-agent builds: keep stages **sequential + self-verified green** to stay coherent; parallel only for independent reads/reviews.

### Next session (finish catch-up, then measure)

1. **Agenda CRUD — the last data-layer subsystem.** `shared/` task/event/recurrence zod schemas (EventKit-shaped JSON); an `agendaEntity` factory (create/rename/delete + value write) reusing the value codec + `pageFile`-style foreign preservation but for `.task.json`/`.event.json`; agenda config-schema CRUD reusing `properties/schema.ts` + a JSON member-strip + `SchemaTransaction`; index population for `agenda_tasks`/`agenda_events` in `build.ts`. Then the data layer is fully caught up to Swift.
2. **Then: the Swift-vs-React line-count diff** (non-comment, shared-functionality-only) — the deliverable in Pending focuses. Run it once agenda lands so the comparison is complete.
3. **Deferred until UI (no-routing directive):** `mutate:*`/`index:*` IPC + preload bridge; incremental index upserts wired into the IPC handler (+ `electron-rebuild`/`asarUnpack` packaging, `loadAll-sync-parents`); cascade orchestration (renamePage→renameCascade revert-on-throw; Context-delete→unlinkTier).
4. **Deferred polish:** wire the pure connection engine into the `readNexus` walk (`linkIndex.byTitle` + `contextsById`); DRY-refactor `readNexus` onto `sidecarIO`/`kind`/schemas + have `build.ts` consume node-exposed `modified_at`/defs instead of re-reading sidecars.

### Pending focuses

- **Glass:** Apple-Regular CSS is the working default; revisit `liquid-dom` only when HTML-in-Canvas ships unflagged. `Surface` is the swappable seam.
- **Window corner radius** (`--glass-radius`, currently 12px) — eyeball against the actual macOS window for concentricity (window radius − 5px inset).
- **Contexts in `~/test`:** the test nexus has no `.nexus/`/contexts, so the sidebar shows Vaults only. Add a couple of Areas/Topics/Projects to the fixture to exercise the Contexts section.
- **Glass Lab** at `glass-lab/index.html` (served via `python3 -m http.server 8765`) — 12-variant comparison page; keep for future glass tuning.
- **Final deliverable (after all data-layer phases):** line-count diff Swift vs React data layer — **non-comment, non-blank lines only**, scoped to *directly shared* functionality. Exclude all button/UIX wiring, MarkdownPM, and Swift's UI-driven cross-relations (e.g. `if clicked then…`) that have no React counterpart pre-UIX. Apples-to-apples data-layer only.

### Fix log

- Sidebar `resolveOrder` ignored its fallback param → adopted ids sorted by hash, not title. Fixed (title fallback for structure mode).
- Sandboxed ESM preload + `__dirname` in ESM main → switched to CommonJS; `sandbox: true` restored.
- Glass: removed `brightness()` + white fill (read too bright over flat dark) → edge-defined Apple-Regular recipe.
