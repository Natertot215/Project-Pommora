## Handoff — Pommora React

Lean current-state snapshot. Read first at session start. Deep docs: data layer → `Planning/Data-Layer-Handoff.md`; design system → `Features/Design.md` + `Features/Typography.md`.

### Where the project is

Two foundations are down; the UI is next.

- **Headless data layer — done** (branch `main`). Phases 0–7 + a 7-agent foundation review; **220 tests, typecheck + build green**, tests-only / no UI wired. The complete write/mutation side caught up to Swift (CRUD, properties, connections, SQLite index, Agenda). Full record: `Planning/Data-Layer-Handoff.md` + `…Build-Log.md`. Swift→React LOC ≈ 8,552 → 2,383 (~72%).
- **Design system — established this session** (branch `design-system`, `404a1d7` + Figma). The Figma "Pommora - React" library is the source of design and is now fully unified: typography ramp finalized; **one mode-driven chip** with a unified tint; semantic accent; **per-color tint variables removed (54 deleted)**. The React token layer is started — vanilla-extract + Inter wired, `color.css.ts` with the 11 solid spectrum tokens. Spec: `Features/Design.md` + `Features/Typography.md`.
- **App shell — designed, paused.** First-pass spec (window-drag fix + resizable / collapsible sidebar at 1440×900, Swift-matched sidebar sizing) is approved but unbuilt, awaiting a desktop GUI verification. Branch `app-shell` (empty placeholder).

### Lessons learned

- **Verify usages — fills AND strokes — before deleting a Figma variable.** A fills-only sweep left 12 stroke bindings on `label-on-color`, so deleting it left dangling refs. Same lesson as the data layer's `target_kind`: a claim is a hypothesis until checked against the real thing.
- **Figma constraints are real:** variable modes cap at **10** per collection (Pro); `defaultModeId` is read-only (no reorder). The chip picker fit in exactly 10 modes; "auto = Default" was done by setting the chip master's mode, not the collection default.
- **The unified chip tint is a *code* derivation** — Figma can't lighten an arbitrary base, so the exact lightened label lives in the React `Chip` component (`color-mix`), with Figma as the visual reference.
- (Data layer) Keep greenfield multi-agent stages sequential + self-verified green; `ELECTRON_RUN_AS_NODE=1` breaks GUI launches (strip it); CommonJS main/preload.

### Next session

1. **App shell** — verify the paused first-pass on desktop, then build it (the "general app functionality" pass: window drag, resizable / collapsible sidebar).
2. **Design system → code** — author the remaining tokens (labels, accent, backgrounds, fills, states, the chip-tint rule, typography) as `design/tokens/*.css.ts`; then build the first components (Button, Chip, …) from the library, the **Chip owning the unified-tint derivation**.
3. **Data layer → UI** (the long-standing UI-gated work): `mutate:*` / `index:*` IPC + preload bridge; incremental index upserts (+ `electron-rebuild` / `asarUnpack`); cascade orchestration. See `Planning/Data-Layer-Handoff.md`.

### Pending focuses

- **`@/design` alias** — add to `tsconfig` + Vite when the first component imports tokens.
- **Glass / Surface** — Apple-Regular CSS default; `Surface` is the swappable seam; `--glass-radius` (12px) — eyeball window concentricity. `liquid-dom` shelved.
- **Contexts in `~/test`** — no `.nexus/` / contexts in the fixture, so the sidebar shows Vaults only; add a few Areas / Topics / Projects to exercise it.
- **`red` is in the solid spectrum but not a chip color** (excluded by design; the mode cap is 10). `grey-default` kept as the `Default` chip color's source.

### Fix log

- `label-on-color` removal: first sweep was fills-only → 12 stroke bindings missed + the variable left dangling. Re-swept fills + strokes (12 vectors → `label-primary`), then deleted.
- Per-color cleanup: usage-check first showed **all 55 in use** (lavender = accent, 100+ uses) → migrated (accent → semantic tokens; gallery → modes; spectrum → solids) before deleting **54** tint variables.
- (Data layer) `SchemaTransaction` rollback hole + `.bak-` sweep (`d712999`); index `target_kind` = `area`/`topic`/`project`, not `context_tier` (`8309e20`).
