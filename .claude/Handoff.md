## Handoff — Pommora React

Lean current-state snapshot. Read first at session start.

### Session summary

The **headless data layer** is underway and building cleanly. After a 20-agent dual-research pass (Swift bloat × TS-native recreation; synthesis in `Planning/Data-Layer-Design.md`, load-bearing claims verified against real Swift — which caught + fixed a tier-shape doc bug in the Swift project's CLAUDE.md), shipped data-layer **Phases 0–4** as green commits: contracts + value codec + atomic I/O → page file engine (foreign-preserving) → sidecar schemas/kind/IO → folder + page CRUD + reorder → **properties (4a value write, 4b schema CRUD + tier synthesis + SchemaTransaction)**. **173 tests; typecheck + build green.** Tests-only, zero UI wired (per directive). Earlier this session also landed the navigation spine (`80e210e`). Per-phase record + all ⚐ review flags in `Planning/Data-Layer-Build-Log.md`.

### Lessons learned

- Apple Liquid Glass over flat dark reads dark + edge-defined — never a brightened/white-tinted panel. Stop iterating a cosmetic detail when it blocks momentum; set it aside and build.
- `ELECTRON_RUN_AS_NODE=1` in this env breaks every GUI launch — strip it. Electron's ESM `require('electron')` fails → CommonJS main/preload.
- Greenfield multi-agent builds: keep stages **sequential + self-verified green** to stay coherent; parallel only for independent reads/reviews.

### Next session (continue the data layer)

1. **Phase 5 — connections & tier relations** — `connections/*` (pure Map-based `[[Title]]` resolve, nexus-wide title uniqueness, title-only no IDs) + `crud/cascade.ts` (rename cascade rewrites inbound `[[links]]`; revert on fail) + `unlinkTier` (Context-delete cascade strips `_tierN` from members, using `tierPropertyId`). Extend the `readNexus` walk to collect `linkIndex.byTitle` + `contextsById`.
2. **Phase 6 — SQLite index** — `index/*` with verbatim 11-table DDL + `better-sqlite3` behind `db.ts` + version handshake + `electron-rebuild`/`asarUnpack`; best-effort upserts wired into `crud/*` (swallowed); off the read path, degrade-to-files on load failure.
3. **Agenda CRUD** — folds into the above via an `agendaEntity` factory reusing `folderEntity` + the value codec; agenda config-schema CRUD reuses `properties/schema.ts` + a JSON member-strip.
4. **Deferred polish:** DRY-refactor `readNexus` onto `sidecarIO`/`kind`/schemas (net code removal) once singleton schemas land — verify against the read-engine tests. `mutate:*` IPC + preload bridge stay deferred until UI (no-routing directive).
5. **After all phases:** the Swift-vs-React data-layer line-count diff (non-comment, shared-functionality-only) — see Pending focuses.

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
