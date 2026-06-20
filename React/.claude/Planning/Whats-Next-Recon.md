# What's-Next Recon — four perspectives (synthesis pending, post-compact)

Four independent agents reported on the most meaningful next work for the React build. Captured here so the **synthesis survives the compact** — the next step is to read this and produce a single recommended roadmap. They converge strongly.

## Perspective 1 — Code readiness map (foundation)

Per-area status:
- **Data layer** — DONE (headless, 220 tests): CRUD, properties (schema + value), connections engine, SQLite index, Agenda. Zero placeholders. Only missing: read-side IPC bridges (`index:*`, property read).
- **Properties** — write/schema DONE; **read into renderer MISSING**. `ViewRow.frontmatter` is optional + `TableView` already auto-derives property columns — but nothing fetches frontmatter into rows. Architecturally ready; the gap is UI rendering (editors + controls), not data.
- **Connections** — engine DONE (scan/resolve/rewrite/cascade); **UI rendering MISSING** (no wikilink decoration, backlinks, tooltips).
- **Page editor** — STUBBED. `DetailPane` page branch renders the literal string "Page: … — render coming next". Read path (`page:open`→`PageDetail` w/ frontmatter+body) works; `react-markdown` installed + unused; no CodeMirror; `updatePageBody` exists but isn't a `mutate` op nor bridged.
- **Navigation/shell** — MOSTLY DONE (sidebar, selection routing, window chrome, resize). Remaining is cosmetic (component-library swap).
- **Table** — read-only DONE (TanStack + pure pipeline, tested). Missing: group/filter/sort UI controls, cell editors, frontmatter data.
- **Gallery** — MISSING (no component; `ViewMode='gallery'` unused).
- **Component library** — tokens DONE; **components ~zero** (`design-system/components/` is README-only). Everything in-app is ad-hoc inline (sidebar rows in `styles.css`).
- **DnD** — engine DONE (Lab); sidebar `useTreeMove` adoption built.

**Highest-unblock shortlist:** (1) **page render/editor** (removes the biggest wall, unblocks properties/views), (2) **component library** (esp. Row — enables the UIX pass), (3) DnD app integration, (4) Gallery. Critical path: editor → property editors → component library → UIX pass.

## Perspective 2 — Product value / path to usable

**Headline: "a beautiful front door and an empty house."** The journey is solid from open→navigate→organize, then **falls off a cliff at read→edit→view**. Clicking a page yields a placeholder string — the wall.

Journey gaps ranked: (1) **read a page** = TOTAL BLOCKER, (2) **edit a page** = TOTAL BLOCKER ("a notes app you can't write in is a viewer"), (3) Table is Title-only demoware (no frontmatter), (4) properties absent, (5) gallery absent, (6) connections unrendered, (7) organize ✅ works, (8) open/navigate ✅ excellent.

**Top 3 by value:** A — render+edit a page (~2 sessions; foundation already there); B — load frontmatter → light up the real Table (~1–1.5; pipeline already consumes it); C — properties surface + cell editors (~2; after A+B).

**The ONE thing: build the page editor (render + write).** Highest value-per-effort — removes the hardest wall, effort is low (wiring, not new subsystem — read + `updatePageBody` exist), and unblocks the whole downstream chain. **Paradigm decision to confirm first: CodeMirror (source+decorations, file-canonical, recommended) vs WYSIWYG.** A plain `<textarea>` could prove the loop in <1 session.

## Perspective 3 — Swift-parity gap

**Back-half parity CLOSED (React's data layer ~72% LOC, exceeds Swift on foreign-data preservation); user-facing parity ~0.** By usable surface React is ~20% of Swift (not the LOC-implied ~75%).

Critical-path parity gaps (Swift shipped-stable, React missing): read-only page render; Table with real property data + cell editors; properties UI + connections rendering; design-system components (gate everything).

**Prioritized: (1) components (Button/Menu/Label/Separator — prerequisite), (2) read-only page render, (3) Table property columns + cell editors + surface group/filter, (4) connections rendering + autocomplete.** Editor (write) is legitimate parity but larger — just after the next 3–4.

**Explicitly DO-NOT-CHASE (Swift in-flux, "don't go ahead"):** the whole toolbar/Views-button/banner chrome thread (Swift's active, self-described-shaky work), group-header drag + drag-between-groups bug, disclosure-chevron animation, block editor/Homepage, EventKit sync.

**Doc corrections:** drag-to-move IS wired (docs say deferred — they conflate it with PommoraDND sort-engine adoption, which IS Lab-only); the "core 7 ~75%" framing undersells the UI gap.

## Perspective 4 — Component library / UX foundation (Nathan's pointer)

Token layer genuinely complete (vanilla-extract, typed); **`chip.css.ts` is the one real component + the proven template.** `components/` is README-only. The app bypasses both the component layer AND mostly the typed tokens (rides CSS-var bridge in `styles.css`).

**The bad drag UX is a `Row` problem, not "no components" broadly.** Why it feels bad + how a real `Row` fixes it: (a) no drag handle → whole row is grab target, fights select (papered over by a `suppressNextClick` hack) → Row with a **drag-handle affordance**; (b) **no drop-indicator slot** → only the container highlights, no "lands here" line → Row with a drop-indicator slot (biggest perceived-quality lift); (c) fragile inline hit-geometry (`paddingLeft` math, dead `.children` class) → Row owns tokenized layout; (d) the drag ghost re-implements the row as a bare label → render the same `Row`; (e) loose class-splicing for states → typed state union.

**Sequencing:** 1 — Separator + Button (prove the token→component→showcase pipeline cheaply; replace the two inline buttons already tagged "replace with design-system Button"). 2 — **Row** (subsumes Leaf+Disclosure; slots incl. handle + drop-indicator; tokenized indent/height; typed states). 3 — re-skin the sidebar onto Row (rewrite, don't amend). 4 — DnD adoption onto the real slots (resolve the two-engine fork). 5 (defer) — MenuItem/Menu/Label/segmented (only load-bearing when in-app menus replace native).

**Pre-token gap to surface:** spacing + radius are still ad-hoc literals; Row needs them — argues for a minimal `space`/`radius` scale from Figma first (or Row carries literals temporarily). A real fork for Nathan.

## Convergence + open forks (for the synthesis)

**Strong convergence:** all four put **page render/editor** at or near #1, and **the component library (esp. a `Row` primitive)** as the other pillar (it's the fix for the drag UX Nathan flagged + the prerequisite for every UI surface). **Properties-into-Table** is the agreed #3, gated on the first two. The work is overwhelmingly "render the finished back-half + give it real components," not new subsystems.

**Open decisions to put to Nathan in the synthesis:**
1. **Editor: CodeMirror vs WYSIWYG** (paradigm — confirm before installing; recommendation CodeMirror).
2. **Sequencing: components-first (Row, fixes the drag UX + enables clean UI) vs editor-first (removes the biggest user wall).** Parity lens says components-first (prerequisite); product lens says editor-first (biggest wall). Likely: a thin read-render now, then Row, then editor + properties.
3. **Two-engine fork:** sidebar `useTreeMove` (bespoke, index-less moves) vs unifying under the reviewed PommoraDND seam. Resolve during the Row/DnD step.
4. **Tokenize `space`/`radius`** before Row, or let Row carry literals.

**Doc fixes to fold in:** drag-to-move is wired (not deferred); only the PommoraDND *sort* engine is Lab-only.
