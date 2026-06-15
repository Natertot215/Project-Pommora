## Handoff — Pommora React

Lean current-state snapshot. Read first at session start.

### Session summary

The **headless data layer is fully caught up to Swift.** After a 20-agent dual-research pass (Swift bloat × TS-native recreation; synthesis in `Planning/Data-Layer-Design.md`, load-bearing claims verified against real Swift — which caught + fixed a tier-shape doc bug in the Swift project's CLAUDE.md), shipped **Phases 0–7** as green commits: contracts + value codec + atomic I/O → page file engine (foreign-preserving) → sidecar schemas/kind/IO → folder + page CRUD + reorder → properties (value + schema CRUD + tier synthesis + SchemaTransaction) → connections & tier relations (pure-Map engine + renameCascade + unlinkTier + setPageTier) → SQLite index (better-sqlite3 behind db.ts; byte-compatible 11-table schema + version handshake + upserts + cold build) → **Agenda CRUD (Tasks + Events: item factory + index pop + config-schema CRUD via a generalized schema-target)**. **220 tests; typecheck + build green.** Tests-only, zero UI wired (per directive). Earlier this session also landed the navigation spine (`80e210e`).

Then a **full foundation code review + hard DRY pass (review-certified)** — a 7-agent adversarial review, every load-bearing finding re-verified against source, fixed across 9 green commits: criticals (a `SchemaTransaction` rollback hole + dangerous backup-sweep; a tier `target_kind` bug; lenient colors; a typed `ErrorCode` union; the `.md`/`.task.json` name guard) and a hard DRY pass collapsing duplicated helpers to single owners (`isPlainObject`, `applyPropertyValue`, `readJsonObject`, `pathExists`, `coerce.ts`, tier field/id construction). Full record + flag adjudication (Fixed / Kept-by-design / Deferred-with-reason) in `Planning/Data-Layer-Build-Log.md` § Foundation Review. Everything outstanding is **deferred-until-UI** (IPC/incremental-upsert wiring) — no catch-up scope and no open correctness flags remain.

### Lessons learned

- Apple Liquid Glass over flat dark reads dark + edge-defined — never a brightened/white-tinted panel. Stop iterating a cosmetic detail when it blocks momentum; set it aside and build.
- `ELECTRON_RUN_AS_NODE=1` in this env breaks every GUI launch — strip it. Electron's ESM `require('electron')` fails → CommonJS main/preload.
- Greenfield multi-agent builds: keep stages **sequential + self-verified green** to stay coherent; parallel only for independent reads/reviews.
- **Verify review findings against source before acting** — the foundation review's headline critical (tier `target_kind`) flipped my own earlier 7b conclusion; an agent's "Swift accepts fractional seconds" was also wrong on inspection. Both directions caught only by reading the real Swift. Treat every finding (mine or an agent's) as a hypothesis until the code proves it.

### Next session (the data layer is done — what's left is UI-gated + polish)

The foundation is review-certified; what remains is wiring it to a UI, not more data-layer logic.

1. **Deferred until UI (no-routing directive):** `mutate:*`/`index:*` IPC handlers + the preload bridge (renderer methods are typed stubs today); incremental index upserts wired into the IPC handler after each mutation (+ `electron-rebuild`/`asarUnpack` packaging so main can load better-sqlite3, + `loadAll-sync-parents`); cascade orchestration (renamePage→renameCascade revert-on-throw; Context-delete→unlinkTier before removing the folder).
2. **Deferred-with-reason (see build log § Foundation Review):** (a) `build.ts` re-reads container sidecars `readNexus` already parsed — the clean fix is a side-channel `readNexus({ collectSidecars })` (NOT sidecar fields on display nodes, which bloat the renderer payload); do it when the index is wired. (b) Wire the pure connection engine into the `readNexus` walk (`linkIndex.byTitle` + `contextsById`) once a consumer exists. *(The old "refactor readNexus onto sidecarIO/schemas" item is **refuted** — it would couple the lenient display read to the typed write contract; the real dup there is already deduped.)*
3. **Real UI** — rebuild from the Figma Component Library; that's when the IPC wiring above lands.

### Pending focuses

- **Glass:** Apple-Regular CSS is the working default; revisit `liquid-dom` only when HTML-in-Canvas ships unflagged. `Surface` is the swappable seam.
- **Window corner radius** (`--glass-radius`, currently 12px) — eyeball against the actual macOS window for concentricity (window radius − 5px inset).
- **Contexts in `~/test`:** the test nexus has no `.nexus/`/contexts, so the sidebar shows Vaults only. Add a couple of Areas/Topics/Projects to the fixture to exercise the Contexts section.
- **Glass Lab** at `glass-lab/index.html` (served via `python3 -m http.server 8765`) — 12-variant comparison page; keep for future glass tuning.
- **Line-count diff — DELIVERED.** Swift vs React data layer, non-comment/non-blank, shared-functionality-only (UI / MarkdownPM / DI / adoption-flow / the deferred query surface excluded both sides): **Swift 8,552 → React 2,383 SLOC, ~72% reduction.** The −92% on CRUD managers (factory consolidation) is the bulk; connections is the one area React is slightly larger (pure-Map resolve vs Swift's SQLite-backed). Counter at `/tmp/sloc.mjs` (throwaway).

### Fix log

- Sidebar `resolveOrder` ignored its fallback param → adopted ids sorted by hash, not title. Fixed (title fallback for structure mode).
- Sandboxed ESM preload + `__dirname` in ESM main → switched to CommonJS; `sandbox: true` restored.
- Glass: removed `brightness()` + white fill (read too bright over flat dark) → edge-defined Apple-Regular recipe.
- Foundation review: `SchemaTransaction` rollback could lose a target on a mid-commit rename failure (failing entry's backup wasn't restored); `.bak-` sweep could delete the only copy. Fixed (`d712999`).
- Foundation review: index `context_links.target_kind` was `'context_tier'` (wrong); it's `area`/`topic`/`project` per `RelationTargetKind.swift`. Fixed + test corrected (`8309e20`).
