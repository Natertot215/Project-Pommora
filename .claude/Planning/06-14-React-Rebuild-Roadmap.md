## React Rebuild Roadmap — Pommora on React + TypeScript + Electron

> **Status:** Exploratory (post-v1 hypothetical). This is a program-level roadmap, not an executable task-plan. Each phase becomes its own `writing-plans` task-plan when greenlit. Phases and steps only — no dates.

**Goal:** Rebuild Pommora from the ground up as a React + TypeScript + Electron app, behavior-identical to the current PRD, leaving SwiftUI/AppKit behind entirely.

**Approach:** Don't translate Swift — rebuild the functionality the TypeScript way. Work happens against a dedicated **test nexus**; the on-disk file model stays the portable contract, but the data layer is rebuilt to React/TS best practices (not transliterated from Swift). Headless libraries supply behavior; the Figma design system supplies all visuals; Pommora's own domain logic (drop semantics, property serialization, frontmatter merge, the index) is written fresh as pure, tested TS.

**Tech stack:** electron-vite · React + TS (strict) · Zustand + TanStack Query · TanStack Table/Virtual · Pragmatic drag-and-drop · headless-tree · Base UI + cmdk · Motion · better-sqlite3 + Kysely · eemeli/yaml · write-file-atomic · Phosphor · Vitest + Playwright. Editor = **CodeMirror 6** (locked).

### Rebuild scope (locked)

The initial rebuild is the proven back half + the two shipped renderers + editor + navigation — **nothing from the spec-only frontier.**

**In scope (the 7):** data layer (incl. Task/Event entities — schema only, no surfacing) · properties · connections · markdown editor (CodeMirror 6) · navigation (shell + sidebar + nav dropdown) · Table view · Gallery view.

**Deferred (post-rebuild frontier):** block editor (Contexts-as-blocks + Homepage) · Agenda surfacing + any calendar sync · Board / List / Cards renderers · Settings editing UI · global search · LLM-chat inspector · type-to-find · OS integrations (menu-bar / Quick Capture / Spotlight / Share — Electron's own `Tray` covers basic menu-bar; a thin native Swift helper only if deeper hooks are ever wanted).

---

### Load-bearing constraints (carried from the PRD)

These are not negotiable and shape every phase:

1. **Files canonical.** Pages are `.md` (frontmatter + body); everything else is JSON sidecars. SQLite is a regeneratable index holding zero canonical data. Kind authority is the parent Type folder's sidecar.
2. **Foreign data preserved by value.** Any frontmatter key Pommora doesn't model must round-trip untouched (comments + order). This is the single highest silent-corruption risk — gated by a byte-stable round-trip test in Phase 2.
3. **Filename = title.** No `title` field; rename = file rename.
4. **Agent-legible.** Every entity is a file an external agent can read/write directly.
5. **No "Pommora" in on-disk schemas.** Brand name reserved for the module/app/docs only.

### Forks to confirm before Phase 1

| Fork | Recommended default | Why it matters |
|---|---|---|
| **Single-window vs multi-window** | **Single-window now, multi-window-ready seams** (CONFIRMED) | Ship single-window (faithful — even in Swift, PagePreview is a child panel sharing the store), but build behind three seams so multi-window is *additive*, not a rewrite: (1) the live-refresh bus is a swappable transport (in-process `mitt` now → `ipcMain`/`BroadcastChannel` later), (2) canonical data stays main-owned + Query-cached per renderer (already multi-window-safe), (3) windows are identified by serializable `PageRef`s. Avoid any global singleton holding shared mutable client state. |
| **On-disk format** | **Modernize, TS-native** (CONFIRMED) | Fresh test nexus → clean serialization: tagged PropertyValue everywhere (explicit type tag, no shape-inference), zod-validated, grandfathered cruft dropped (e.g. `pommora_table_widths`). Stays agent-legible JSON + frontmatter; no longer byte-compatible with the Swift app (which is left behind). |
| **Markdown engine** | **CodeMirror 6** (CONFIRMED) | Lower-level than Milkdown — full decoration/transaction control, which the Pommora-specific rendering (wikilinks, embeds, dynamic-syntax) needs. |
| **Type-to-find in sidebar/table** | **Out of scope** (CONFIRMED) | Dropped from the rebuild. |

---

### Module structure (target)

Split by responsibility, main-process vs renderer boundary explicit:

- `src/shared/` — TS contract types imported by both sides (entities, IPC channel signatures, PropertyValue, SavedView).
- `src/main/` — Node/Electron only: `fs/` (atomic IO, frontmatter merge, trash, folder-filter), `index/` (better-sqlite3 + Kysely: schema, builder, updater, query), `adoption/`, `ipc/` (typed handlers), `window/`.
- `src/preload/` — contextBridge typed wrapper.
- `src/renderer/` — React: `state/` (Zustand bundle + Query), `design/` (tokens, `<LiquidGlass>`, components), `sidebar/`, `detail/` (`pipeline/`, `table/`, `gallery/`, `view-settings/`), `properties/`, `editor/`, `contexts/`, `homepage/`, `agenda/`, `settings/`.

---

### Phase 0 — De-risk spikes (the gates)

Prove the two genuine risks before committing to the full build. Throwaway code.

- [ ] Spike A — **Glass shell:** transparent Electron `BrowserWindow` + the **`liquid-glass-react`** component (rdev; live playground at liquid-glass.maxrovensky.com) — Chromium-only shader refraction, ideal since Electron is all-Chromium (no Safari/Firefox fallback needed). **Locked settings: saturation 100%, corner radius 26, blur 0.3** (refraction mode + displacement/chromatic/elasticity tuned to Figma). Confirm it matches the Figma glass and holds FPS with the sidebar pane using it.
- [ ] Spike B — **Hard table:** TanStack Table + Virtual grouped/disclosure rows + Pragmatic drag-reorder across groups, with a row unmounting mid-drag under virtualization. Confirm the insertion-line + cross-group drop commit works.
- [ ] Confirm the four forks above.
- [ ] **Gate:** both spikes land → proceed. If glass fidelity or table-drag fails, reassess before investing further.

### Phase 1 — Foundation & scaffold

- [ ] Scaffold via `npm create @quick-start/electron` (react-ts), electron-vite v5, contextIsolation ON / nodeIntegration OFF.
- [ ] TS strict config, path alias for `src/shared`, ESLint + Prettier.
- [ ] Vitest (unit) + Playwright (e2e) wiring; CI with `@electron/rebuild` for native addons.
- [ ] Typed IPC bridge (~100 lines): shared contract types, contextBridge wrapper over `ipcMain.handle`/`invoke`, one main→renderer event channel.
- [ ] `electron-builder` + `electron-updater` skeleton (signing/notarization deferred to Phase 12).

### Phase 2 — Data layer (the spine)

All main-process, exposed via IPC. Pure-logic ports written fresh + tested.

- [ ] `src/shared` entity types: Areas/Topics/Projects, PageType/Collection/Set, Page, AgendaTask/Event, sidecars, settings, homepage.
- [ ] Atomic file IO: `write-file-atomic` (temp+fsync+rename); soft-delete to `.trash/`; same-file/recase detection (stat ino+dev); `FolderFilter` (NFC + case-fold, symmetric at discovery + index).
- [ ] **Frontmatter merge** on `eemeli/yaml` Document API: substitute modeled keys only, pass foreign keys + comments through, `sortKeys:false`. **Add read→write→assert-byte-stable test (constraint #2).**
- [ ] **PropertyValue** (de)serializer: TS-native **tagged** on-disk format (explicit type tag per value — no shape-inference), zod-validated schema per property type + round-trip tests. (Modernized: agent-legible, unambiguous.)
- [ ] SQLite index (better-sqlite3 + Kysely): schema, `PRAGMA foreign_keys=ON`, JSON1 property filters, `COLLATE NOCASE` title index; `IndexBuilder` (full scan, skip-bad-row), `IndexUpdater` (incremental upsert; `INSERT OR REPLACE` leaf vs `ON CONFLICT DO UPDATE` cascade-parent), `IndexQuery` (the queries views/resolver run), `loadAll` defensive re-upsert sweep.
- [ ] Adoption scan: depth-2, sidecar inference, auto-tag missing sidecars, ULID-collision healing, promise-based consent gate.
- [ ] `SchemaTransaction`: two-phase multi-file commit (stage `.txn-` temps → rename → restore on fail → sweep stale).

### Phase 3 — State & app shell

> **Multi-window-ready discipline (single-window now):** build the three seams below so a second window is additive. UI/client state is per-renderer (each window legitimately has its own selection/scroll); only "data changed → re-fetch" crosses windows, through the bus seam.

- [ ] Zustand vanilla store bundle, fresh isolated instance per active Nexus (createStore in context, disposed on swap). Module-level `getState()` accessor is for **intra-window** imperative reach only — never the cross-window channel (a renderer global is invisible to other renderers; anything reaching another window goes through main).
- [ ] TanStack Query over the IPC data layer (queries = reads, mutations = writes, entity-id query keys). **This is the multi-window seam for data:** canonical data is main-owned; each renderer holds its own Query cache and re-derives — windows never share mutable data state.
- [ ] **Live-refresh bus behind a swappable transport interface** (`emit(changedIds)` / `subscribe()`): backed by in-process `mitt` now; the multi-window swap is `ipcMain` broadcast → `BroadcastChannel` with zero call-site changes. Drives `invalidateQueries`; kept distinct from store property-subscriptions.
- [ ] Nexus open/switch lifecycle, launch flow (folder grant; launch modals handled), settings load + label wiring + accent var.
- [ ] Window/route identity via serializable `PageRef` (`{pageID, vaultID, collectionID?, setID?}`) re-resolved against live stores, tolerates dangling refs. **This is the multi-window seam for windows:** opening a second real window later = instantiate another renderer with a different `PageRef` (the PagePreview child-panel pattern, generalized) — no marshaling retrofit.

### Phase 4 — Design system & component library

- [ ] Token pipeline: Figma variables → CSS custom properties (colors, spacing, radii incl. squircle, type scale, runtime `--accent`, dark mode via `prefers-color-scheme`).
- [ ] Productionize `<LiquidGlass>` (two tiers: full refraction for floating chrome; cheap flat-fill for high-count surfaces). Every popover/dropdown shell wraps itself (no system chrome on web).
- [ ] Core components from Figma: buttons, labels, chips, fields, segmented controls, menu items/headers, separators, selection chrome.
- [ ] Storybook mirroring the in-app component explorer (UIX).

### Phase 5 — Sidebar

- [ ] headless-tree wiring: Contexts tiers (Areas/Topics/Projects), Vaults (PageType → Collection → Set → Pages), pins/recents, calendar pin entry.
- [ ] Selection model: string tag → rich entity; non-selectable-but-expandable rows (`canSelect` predicate); keyboard nav skipping disabled rows.
- [ ] Inline rename lifecycle: programmatic focus + select-all on stub-create, Enter-commit/Esc-cancel/blur-cancel with in-flight guard.
- [ ] Reorder (Pragmatic): within-list tier reorder; two-zone merged collections-above-pages reorder with cross-zone rejection.
- [ ] Sections: disclosure, hover-reveal `+`, inline-renameable headers; homogeneous-row structure (no flat/disclosure mix per the old crash lesson — N/A in React but keep rows uniform).

### Phase 6 — Detail surfaces & Views pipeline

- [ ] Pure view pipeline (fetch → filter → group → sort) as pure TS functions + ported test corpus (locale collation + UTC date boundaries pinned).
- [ ] Table renderer (TanStack Table + Virtual): grouped disclosure rows, columns (resize/reorder/show-hide retaining hidden state), inline cell editors (Base UI popover, **on-dismiss** commit), memoized to reproduce anti-jank guards.
- [ ] Gallery renderer: CSS grid + cards, card zones (`VisiblePropertyOrder` shared with table columns — DRY).
- [ ] Shared drop model (Pragmatic): pure planner (`reorder | move | rewriteProperty | none`) by group KIND, anchor-id commit, grid geometry hit-test over on-screen card-frame registry, insertion-line + group-highlight overlays from one observable state.
- [ ] View Settings (Base UI chromeless popover + app-owned in-popover route stack + ResizeObserver auto-height): sort/filter/group/layout/property/storage panes; `updateView` whole-config rewrite.

### Phase 7 — Properties & Connections

- [ ] Property type system (discriminated TS unions, exhaustive switch with `never` default at every dispatch site), per-type cell editors, FrontmatterInspector.
- [ ] Context-tier links (tier1/2/3): ContextPicker, value editor, display resolver (icon + title), stored by ID array (`[{$rel}]`).
- [ ] Inline connection rendering outside the editor (styled colored wikilink-style text in property/context displays).
- [ ] Select-options + status-groups editors (shared chip + insertion-line drag feedback).

### Phase 8 — Page editor host (CodeMirror 6)

- [ ] CodeMirror 6 base wiring as a controlled React component.
- [ ] Editor host: frontmatter↔body model, debounced save (300ms) + synchronous flush on Cmd-S / page-switch / window-blur / before-quit.
- [ ] Pommora decorations: wikilink rendering with **synchronous** in-memory index read, image embeds, `[[ ]]` autocomplete (stale-guarded query).
- [ ] Caret-anchored floating UI overlays; scroll-synced title overlay.
- [ ] Preview panel reusing the host; editor↔app context-menu arbitration.

---

## Deferred — post-rebuild frontier (NOT in the locked 7-item scope)

The phases below are the spec-only frontier. They are net-new product work (no battle-tested Swift reference) and are explicitly **out of the initial rebuild.** Kept here for sequencing once the core ships.

### Phase 9 — Contexts as live blocks & Homepage

- [ ] Area/Topic/Project pages as editable block pages of views/queries (`ContextBlock` model) — never read-only snapshots.
- [ ] Homepage composed-blocks dashboard (`.nexus/homepage.json`).

### Phase 10 — Agenda surfacing

- [ ] Task/Event data already in the layer; surface via the calendar pin entry (no separate Agenda heading).

### Phase 11 — Settings UI

- [ ] Per-Nexus label overrides + accent color editing (storage + wiring already in Phase 3).

### Phase 12 — Polish, packaging & parity audit

- [ ] Motion pass (disclosure, hover-lift, enter/leave, FLIP reorder, scroll parallax); animate transform/opacity only, never blur.
- [ ] Supporting cast: tinykeys shortcuts, sonner toasts, react-resizable-panels, Phosphor icon registry QA against Figma.
- [ ] electron-builder packaging, Developer ID signing + Apple notarization, signed auto-update.
- [ ] **Behavior-parity audit** against the PRD + the ported test corpus; FPS budget confirmation for glass.

---

### Build-your-own inventory (no library covers these)

Ported as pure functions / app logic, language-agnostic: the drop planner + anchor-id commit + grid hit-test (Phase 6); the PropertyValue codec (Phase 2); the order-preserving frontmatter merge (Phase 2, hardest); the two-phase atomic commit + recase/trash layer (Phase 2); the `<LiquidGlass>` primitive (Phase 0/4); the in-popover route stack (Phase 6); the inline-rename lifecycle (Phase 5); the typed IPC bridge (Phase 1).

### Repos to study (reference DNA, not dependencies)

**`rdev/liquid-glass-react`** (the CHOSEN glass component — playground at liquid-glass.maxrovensky.com; settings saturation 100 / radius 26 / blur 0.3) · `shuding/liquid-glass` (refraction-map reference) · `atlassian/pragmatic-drag-and-drop` (virtualization + custom preview examples) · `lukasbach/react-complex-tree` (selection/rename reference) · `electron-vite/electron-vite-react` (updater + native-addon rebuild config) · `eemeli/yaml` (Document API).
