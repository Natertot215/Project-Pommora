## Handoff — Pommora React

Lean current-state snapshot. Read first at session start.

### Session summary

Stood up the React/TS/Electron rebuild from scratch: Phase 1 (read-only window + glass sidebar reading `~/test`) shipped, reviewed, committed. Iterated the sidebar glass to an Apple-Regular CSS recipe (edge-defined; `liquid-dom` evaluated + shelled as experimental). Wrote the full `.claude` folder. Dispatched the Phase 2 build workflow (navigation function + Table/Gallery + page render).

### Lessons learned

- Apple Liquid Glass over flat dark reads dark + edge-defined — never a brightened/white-tinted panel. Stop iterating a cosmetic detail when it blocks momentum; set it aside and build.
- `ELECTRON_RUN_AS_NODE=1` in this env breaks every GUI launch — strip it. Electron's ESM `require('electron')` fails → CommonJS main/preload.
- Greenfield multi-agent builds: keep stages **sequential + self-verified green** to stay coherent; parallel only for independent reads/reviews.

### Next session

1. **Land Phase 2** — review the build workflow's output (selection→detail, view pipeline, Table + Gallery, page render); run it in the GUI (`env -u ELECTRON_RUN_AS_NODE …`); confirm Table renders `~/test` vaults; commit.
2. **Phase 3 — write path** — atomic write + order-preserving frontmatter merge (`eemeli/yaml` Document API + a byte-stable round-trip test — the one real silent-corruption footgun); create/rename/move page.
3. **Phase 4 — properties & connections**, then **Phase 5 — CodeMirror editor**.

### Pending focuses

- **Glass:** Apple-Regular CSS is the working default; revisit `liquid-dom` only when HTML-in-Canvas ships unflagged. `Surface` is the swappable seam.
- **Window corner radius** (`--glass-radius`, currently 12px) — eyeball against the actual macOS window for concentricity (window radius − 5px inset).
- **Contexts in `~/test`:** the test nexus has no `.nexus/`/contexts, so the sidebar shows Vaults only. Add a couple of Areas/Topics/Projects to the fixture to exercise the Contexts section.
- **Glass Lab** at `glass-lab/index.html` (served via `python3 -m http.server 8765`) — 12-variant comparison page; keep for future glass tuning.

### Fix log

- Sidebar `resolveOrder` ignored its fallback param → adopted ids sorted by hash, not title. Fixed (title fallback for structure mode).
- Sandboxed ESM preload + `__dirname` in ESM main → switched to CommonJS; `sandbox: true` restored.
- Glass: removed `brightness()` + white fill (read too bright over flat dark) → edge-defined Apple-Regular recipe.
