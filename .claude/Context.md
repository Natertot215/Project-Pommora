## Context — Pommora React

### Current Focus

The React rebuild of the Swift paradigm reached its finish line at v0.5.0 — Page Previews and the Subfield unification pulled React past where the SwiftUI build ever got. That's the baseline the roadmap counts forward from, not a target still to hit, and it's mostly my own live drive from here.

**v0.6.0 is underway** — the view renderers that only ever existed as names over the finished filter → group → sort pipeline. **Cards** is first: a visuals-first prototype is live on the `cards-view` branch, brainstormed from a ratified Decision Log but deliberately left un-reviewed — a design proof, not the hardened build. The implementation-planning phase is opening now off [[Cards View — Implementation Planning Checklist]]. Table is still the only renderer that ships on `main`; Gallery, List, Calendar, and Timeline are still just names.

Two fixes already shipped off that track: the **persistent thumbnail cache** (B-6) now existence-prunes at nexus-open instead of evicting to a recents∪pins window, so Preview covers persist across sessions; and a **MarkdownPM table** cell-edit bug — edits didn't repaint until a reload — is fixed. The prototype audit came back **harden-in-place** (no rebuild-class findings), so the next track is the hardening pass — the audit's fixes plus the quality-gate slate — with Compact styling parked for sign-off.

### Recent Work

#### Cards View — prototype (07-18)

The first v0.6.0 renderer, built visuals-first on `cards-view`. A ratified Decision Log drove a live, un-reviewed prototype: the renderer seam both the container and embed mounts share, a Set Cards row, flattened disclosure bands, a breadcrumb that doubles as the add-property input, in-band drag, per-value interaction reusing the table's cell leaves, and a two-stage add-picker. It's a design proof rather than the hardened build — no CardsView tests exist and the quality-gate slate is still owed. → [[Cards View — Decision Log]] · [[Cards View — Implementation Planning Checklist]].

#### Unified Subfield + Scan-Promote (07-17)

The floating preview and the full-pane detail had drifted into two copies of the same footer, so this collapsed them. The Subfield takes one optional scope prop now — a scoped instance (the floating preview) describes its own page off a body it owns, never the single shared live-count slot, because a second writer there would evict the main pane's count.

NavView also picked up the List/Gallery toggle the detail pane already had, plus its own persisted view mode kept separate from the NavWindow's, and the scan on the nav/map side promotes the whole NavWindow into a NavView tab. This is the work that closed the rebuild. → [[Subfield]] · [[Navigation]] · `History.md`.

#### Page Previews (07-16 → 07-17)

Directly advancing on the Multi-Tab Nexus momentum, a parked `open_in` value became a real floating, editable preview window — wiki-clicks open dedup-focused tabs beside the origin instead of a back-only peek, and it stays neutral to the app's own tabs.

The page window and the NavWindow are the same thing under the hood: one chrome, one tab-motion layer, one side-pane, one warm seam. Each origin page remembers its opened tabs across sessions in a synced `page-previews.json`. → [[PagePreview]] · `History.md`.

#### Multi-Tab Nexus (07-14 → 07-16)

The nav model had a fork sitting open for around a month — replace the pane, stack top-bar tabs, or split panes — and it mostly came down to the perf hard-rule: N live tables would wreck scroll, so tabs keep one view mounted and cache the rest per-tab.

Pinned tabs ARE the pin set, never a second stored copy; the whole set travels across devices through a synced `tabs.json`, and every tab carries its own Back/Forward. The empty state became NavView, the full-window recents gallery. It's on `nav-gallery-pins`. → [[Navigation]] §II · `History.md`.

#### SurfacePM — Block Surfaces (07-10 → 07-13)

The composable dashboard layer — a mosaic of draggable, resizable tiles over an in-house tessellation engine, with the Homepage as the removable dev host. It works host-agnostic on purpose, so it exists before any real host does, and it repairs rather than rejects at every level: a foreign or broken tile entry renders inert instead of crashing the surface.

A page embed IS the CM6 editor, flipped read-only in place. View embeds, the geometry locks, and the link-graph host are the pieces still left. → [[SurfacePM]] · `History.md`.

#### Navigation Surface + Auto-Scroll (07-14)

A per-nexus nav-state layer — recents, pins, favorites, all resolved live against the tree so a moved entry follows and a dead one just drops on render — feeding a store and client-side fuzzy search behind the NavPane command surface.

Alongside it, every drag's edge-scroll collapsed onto one shared primitive across seven surfaces, resolving its scroller once at drag start rather than chasing the pointer each frame. → [[Navigation]] · [[PommoraDND]] §II · `History.md`.

### Pending Focuses

- Cards hardening pass — the prototype audit verdict is harden-in-place (no rebuild-class findings): the audit's 2 MED + 3 LOW fixes, then the quality-gate slate (CardsView tests, simplifier, a11y), then the deferred features. Compact styling parked for sign-off. → [[Cards View — Implementation Planning Checklist]].
- The NavPane toolbar dropdown is still a blank placeholder — what a compact nav dropdown holds versus the fuller NavWindow is an open call before building into it.
- User Sections CRUD — collections render user sections but there's no way to actually make one (`mutate.ts` has no section ops); its own brainstorm → plan → build. → `Sidebar.md`.
- The flattened-mode bundle — "None"/flat grouping plus Flatten and Hide Location — is deferred; the `flat` GroupConfig kind stays reserved. → [[Views]].
- Perf debt: no row virtualization yet (every row mounts, which bites at thousands), and an external value edit doesn't live-refresh an open table. The one-view-mounted multi-tab design deliberately dodges needing table virtualization.
- Canvas — the spec sits at `Planning/6-26 - Canvas Spec.md`, pending adversarial review → plan → build.
- iCloud-sync readiness (future) — `serializeOnFile` can't coordinate with the iCloud daemon under LWW, `.nexus/index.db` needs sync-exclusion, and the walk has to skip `.icloud` placeholders.
- Mobile iOS companion — parked, spec at `.claude/Mobile/MobileSpec.md`, no build commitment.

### Hard Rules

- The dev app runs against the real Nexus, so CDP opens and Escs only unless authorized — and the editor gets driven only on a throwaway page, since typing into a live one autosaves straight to real data.
- Stage explicit paths, never `git add -A` — parallel sessions and Nathan's own uncommitted edits share the tree.
- Never allow planning, brainstorming, or session-specific references to make it into code or documentation. 

### Lessons

- Two-writers-for-one-fact is the defect class the tab and nav work kept breeding — `tab.target` versus the navStack cursor, the tab set versus the pin set, the capture marker versus the thumbnail file. Every real bug reduced to it, and the fix was always one writer or a lockstep rule.
- HMR only goes so far: CSS and React Fast-Refresh work, but CM6 extension code needs ⌘R, `src/main` and preload need a full dev-process restart, a vanilla-extract `*.css.ts` can serve stale (a plain restart heals it, ⌘R never does), and a component's focus-effect / handler / attribute change often gets skipped by Fast-Refresh.
- CDP has two quirks that keep biting: synthetic clicks work on tabs/rows/buttons but never fire PickerMenu items (drive those via `el.click()` in `Runtime.evaluate`), and a non-integer dpr (1.7 on this machine) throws off screenshot clip math — crop the full-frame PNG with PIL instead.
- Where the recent code lives: Multi-Tab under `Tabs/` (`tabsModel.ts` pure with its own tests, `warmCache.ts` for the session LRU, every tab-bar visual knob in `tabBar.css`'s `.tab-bar` block); `select` is the single nav entry point; the New Tab `+` rides a shared `--toolbar-swallow` var on `.app-toolbar`; and the pin toggle shared between list rows and gallery cards is `NavPinButton` in `NavList.tsx`.

### Fix Log

- `.nexus/activeViews.json` and its per-machine siblings (`folds`, `viewOrders`, `tableHeadingColumns`, `linkTitles`) aren't gitignored — using the switcher on a fresh container creates a would-sync file. They need adding to the Nexus `.gitignore`; `tabs.json` does not, since it's synced on purpose.
- The "File" property icon gets clipped by its vertical row padding on the ViewPane.
- The link-rename field shows a leading empty space — a visual inset, not a stored character (deprioritized).
- Blockquotes inside of codeblocks are unstable and need proper debugging.
- Block-math drag corrupts the doc: a multi-line `$$…$$` span with a blank line inside parses as two halves with orphaned `$$`, and block-dragging it corrupts the document (`blockModel.ts`, test-pinned but unguarded).
- A single-word bullet that wraps drops the word below the marker — only the `line-height` cap made it in so far. → [[MarkdownPM]].
