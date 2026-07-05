## Personalization Config — Decision Log

### Frame

- **Purpose:** DRY all nexus-wide interface personalization into one config system in `.nexus/settings.json`, so adding a new toggle costs ~2 lines instead of a scattered mini-feature.
- **Core Value:** the marginal cost of a personalization knob collapses, and the duplicated default-icon literals collapse to one source — all riding the synced settings file so mobile inherits it for free.
- **Success Criteria:** accent, hide-chevrons, outliner-lines, and default-icons all resolve through one schema + one read + one apply-map + one setter; a new toggle = one schema field + one apply-map row; per-entity icon overrides still win.

### Sources

- `React/src/main/settings.ts` — per-Nexus `settings.json` read/write. Entirely Swift-compat scaffolding (`ensureSettings` backfills Swift-required `version`/`labels`/`modified_at`; `labelsToDisk` snake_cases; `SWIFT_DEFAULTS_VERSION`). Only `subfield` is React-writable via `writeSubfield` (merge-on-write, preserves foreign keys). The seed carries **no** accent/time_format.
- `React/src/main/readNexus.ts:290-376` — the read seam. Accent from `settings.accent_color` via `resolveAccent` (`:293`); timeFormat (`:294`); labels (`:292`); profile (`:297-298`); saved strip **hardcoded** house/calendar/clock (`:317-319`); all surfaced on `NexusTree` (`:365-376`).
- `React/src/main/paths.ts:40-62` — `NEXUS_CONFIG_FILES` registry + `DEVICE_LOCAL_NEXUS_FILES` (folds/activeViews/viewOrders/tableHeadingColumns). `tier-config.json` is **not** registered (Swift orphan on disk).
- `React/src/main/appConfig.ts` — the per-*app* store (`pommora.json` in userData): lastNexusPath/recents/trashMode. Device-level, never synced — the wrong home for nexus-wide personalization.
- `React/src/renderer/src/Detail/Banner/Banner.tsx:14-21,67` — the clean 6-kind `DEFAULT_ICON` record + `iconNameOr(owner.icon, DEFAULT_ICON[kind])`.
- `React/src/renderer/src/Sidebar/Sidebar.tsx:73-78,232,262,288,307,326,343` — `folderAwareIcons(custom, fallback)` resolver + the same defaults re-typed as scattered literals.
- `React/src/renderer/src/design-system/symbols/index.tsx:119` — `iconNameOr = asIconName(value) ?? fallback` (the override primitive).
- `React/src/renderer/src/Detail/Views/Table/Cell.tsx:46`, `.../Table/GroupHeader.tsx:33`, `.../MarkdownPM/AutocompletePanel.tsx:50` — more page/set icon literals; AutocompletePanel ignores a page's custom icon entirely.
- `React/src/renderer/src/store.ts` — accent applied on load (~`:237`); sidebar/inspector widths in localStorage; subfield store wiring.
- `Features/Structure.md:52-54,91` (Settings singleton; "editor planned, hand-edited today"); `Features/Contexts.md:83` (tier-config singleton planned).

### Decisions

#### A — Scope & Home
- **A-1:** [confirmed] Personalization is **nexus-wide** and lives in `.nexus/settings.json` (canonical/synced) — rides to mobile. Never device-local.
- **A-2:** [confirmed] Swift compatibility is **dead** (Nathan) → `settings.json` becomes React-owned; the Swift-shaped seed/backfill/snake_case in `settings.ts` is removable.
- **A-3:** [confirmed] Extend `settings.json` with a `personalization` block — **not** a new `.nexus/` file (fewer reads/files; DRY).
- **A-4:** [confirmed] Accent migrates into `personalization.accent` (from top-level `accent_color`) via a one-time read-migration. Follow-OS (`'system'`) path preserved.

#### B — The DRY Mechanism
- **B-1:** [confirmed] Four fixed pieces: one **zod schema** (typed: booleans/enums/icon-names), one **read** (extend `readNexus` → `NexusTree`), one **apply-map** (`key → effect`, effect ∈ {set-CSS-var, toggle-root-class, expose-value}), one **generic setter** (`setPersonalization(key, value)`).
- **B-2:** [confirmed] **Merge-on-write** (read-modify-write), most-recent-wins on a true collision (Nathan's single-user mobile model).
- **B-3:** [confirmed] **Preserve unknown keys** on write — rationale repurposed from Swift-compat to desktop↔mobile version skew (a toggle one build doesn't know must survive the other's write).

#### C — Default Icons
- **C-1:** [confirmed] Hoist Banner's `DEFAULT_ICON` to a shared `DEFAULT_ENTITY_ICONS` constant = the config seed. Kinds: collection `gallery-vertical-end`, set `folder-closed`, area/topic/project `layout-grid`, page `file-text`.
- **C-2:** [confirmed] Uniform resolution everywhere: `entity.icon ?? config.defaultIcons[kind]`. Per-entity override unchanged.
- **C-3:** [confirmed] Repoint sites: `Banner.tsx:14-21,67`, `Sidebar.tsx:232,288,307,326,343`, `Cell.tsx:46`, `GroupHeader.tsx:33`, `AutocompletePanel.tsx:50` (also fixes its missing-override bug).
- **C-4:** [confirmed] Homepage is **not icon-driven** — it renders the profile image via `NexusHeader.tsx:58,66` (`square-dashed` fallback), so the `icon: 'house'` at `readNexus.ts:317` is **dead data** (the `house` glyph renders nowhere). Homepage is out of the icon config entirely; drop the dead key as a micro-cleanup. Calendar/Recents saved icons (`readNexus.ts:318-319`) stay **fixed in v1** if/when the saved strip renders them.
- **C-5:** [confirmed] Out: `PropertyTypes.tsx` property-type glyphs (semantic, not personalization).

#### D — v1 Toggle Set
- **D-1:** [confirmed] hide-chevrons → toggle a root class; CSS hides the sidebar twisty (`Sidebar.tsx:198`).
- **D-2:** [confirmed] outliner-lines (MarkdownPM nested-list guides) → **pure CSS on `.cm-line`**, NOT a CM6 extension (extensions bake at mount → a live toggle wouldn't take; see G-2).
- **D-5:** [confirmed] connection-color → `personalization.connectionColor: 'accent' | <color>`, default `'accent'`. Apply by overriding `--connection` on `:root` at runtime (the `applyAccent` pattern); when `'accent'`, set `--connection: var(--accent)` so it **auto-tracks** accent changes; an override sets a specific solid. No edit to `theme-vars.css.ts`. **Separate from the parallel URL-link-color feature** (Nathan) — different axis (global inline `[[]]` vs per-URL-property table cells), no shared picker/model. UI deferred (E-1).
- **D-3:** [confirmed] default-icons → delivered by C.
- **D-4:** [confirmed] accent → migrated (A-4), applied via the apply-map, retiring the bespoke path.

#### E — UI
- **E-1:** [assumed] The **settings-panel UI is deferred** to its own design pass — no UI freehanded. v1 toggles are settable in-file (like accent today); `SettingsDropdown` is the eventual home. ← Nathan to confirm.

#### F — Adjacencies / Reconciliation
- **F-1:** [open — for review] `settings.json` gains writers (`writeSubfield` + profile mutate ops + new personalization/accent). Do they need to funnel through **one serialized writer** to avoid a stale-read clobber, or is single-user low-frequency + merge-on-write enough?
- **F-2:** [confirmed] Accent migration must not break the follow-OS (`'system'`) resolution (`readNexus` `resolveAccent` + store `systemAccent`).
- **F-3:** [confirmed] Docs to reconcile once shipped: `Structure.md:52-54,91`, `Contexts.md:83`, any Design/Icons doc naming default glyphs.
- **F-4:** [confirmed] Swift residue now removable — separable cleanup (settings.ts Swift seed; orphan `tier-config.json`; Swift-shaped `state.json`).

### Core (must-have)

- The `personalization` schema + read + apply-map + generic merge-on-write setter (+ IPC + store action).
- Accent migrated into the block, follow-OS preserved.
- Icon DRY: the shared `DEFAULT_ENTITY_ICONS` seed + every C-3 site repointed.
- The three toggles wired to work when set (hide-chevrons, outliner-lines, default-icons).
- Unknown-key preservation + merge-on-write.

#### Prospects (allowed later, not now)
- Settings-panel UI — its own design pass; don't-foreclose: apply-map is UI-agnostic, a panel just calls `setPersonalization`.
- Saved-strip icons configurable — needs a saved-keyed sub-map.
- More toggles (each ~2 lines once the system lands).
- Swift-residue sweep (F-4).
- A per-*app* preferences pass (theme source, window bounds, panel widths) in `pommora.json` — different sync scope.

#### Out of Scope (won't do)
- Per-app / per-device prefs — they belong in `pommora.json` (device-level), not the synced personalization block.
- The four device-local `.nexus/` UI-state files — transient state, not personalization; must stay unsynced.

#### Considered & Rejected
- A separate `.nexus/personalization.json` — more files + an extra read/sync target; fights the DRY goal. `settings.json` already reads on open.
- Personalization in `pommora.json` — wrong scope; it wouldn't sync per-nexus (the opposite of the goal).

#### Lessons
- Personalization **syncs**; UI state **doesn't** — keep the boundary the mobile work established.
- The apply-map's three effect kinds (CSS-var / root-class / expose-value) cover every knob on the table — **except editor-side effects** (CM6 bakes at mount), which must be pure CSS.

### Review Round 1 (build-breaker) — Folded

Round-1 attack grounded against real code; all six folded. The DRY architecture held; **concurrency was the real gap.** This section refines the decisions above.

- **G-1 (was F-1) · HIGH:** `settings.json` has multiple UNSERIALIZED read-modify-write writers — `ensureSettings`, `writeSubfield`, and `setProfileImage`/`setProfileSubtitle` (in `mutate.ts:220-255` via `mutateJson`, **not** `index.ts` — corrects Sources §settings.ts), plus the new `setPersonalization`/accent. Concurrent writes to *different* keys silently clobber (executed repro: 20/20 lost a key). **Fix:** funnel every settings-path write through the per-file serialize lock in `io/fileLock.ts` — the F1 pattern already wired to page/cascade writes. Prerequisite; lands first.
- **G-2 (was F-2):** outliner-lines is **pure CSS on `.cm-line`**, not a CM6 extension (D-2).
- **G-3 (was F-3):** hide-chevrons uses `visibility:hidden` (not `display:none`) and the same root class hides the leaf `.twisty-spacer` (`Sidebar.tsx:113`), or disclosure vs leaf rows desync horizontally.
- **G-4 (was F-5):** accent migration uses a back-compat read — `resolveAccent(settings.personalization?.accent ?? settings.accent_color)` — and updates `readNexus.test.ts` + `mutate.test.ts` in the same task. Follow-OS confirmed safe (renderer consumes only the resolved `tree.accent`).
- **G-5 (was F-6):** the icon hoist seeds the folder open/closed swap pair (`folderAwareIcons`, `Sidebar.tsx:78`) from the shared constant too.

### Build Sequence (ratified)

1. **Settings-write serialization (G-1)** — wrap every `settings.json` writer in the `io/fileLock` per-path lock + a concurrency test proving no key-loss. Prerequisite.
2. **Schema + read** — `Personalization` zod type (accent, connectionColor, hideChevrons, outlinerLines, defaultIcons); extend `readNexus` → `NexusTree` with the G-4 back-compat accent read.
3. **Setter + bridge** — `setPersonalization(key, value)` (merge-on-write, serialized) + IPC + preload + store action.
4. **Apply-map** — one `key → effect` table applied on load + on change; move accent + connection onto it.
5. **Icon DRY** — hoist `DEFAULT_ENTITY_ICONS` (incl. G-5 swap pair) to shared; repoint the C-3 sites; drop the dead `house`.
6. **Toggles** — hide-chevrons (G-3), outliner-lines (G-2 CSS), connection-color (D-5), default-icons.
7. **Reconcile docs** (F-3) + optional Swift-residue sweep (F-4).

### Parallel-Session Overlap (build-time)

Uncommitted parallel URL-link-color work sits in the tree and overlaps files this build touches: `main/index.ts`, `preload/index.ts`, `Detail/Views/Table/Cell.tsx`, and `MarkdownPM/AutocompletePanel.tsx`. Edits interleave in the same files, so a clean `git add <file>` would sweep their work in — coordinate the commit (defer to their commit, or isolate); never `git add -A`.

### Status — Implemented (green)

Shipped across the build; typecheck clean, full suite green (1166 tests). Notes that refine the plan:

- **Outliner-lines is pure CSS, not a decoration — better than G-2 required.** List lines already carry a per-line `--li-level` var + a uniform `--list-indent`, so the rail is a `::before` on the existing `.md-li` class, gated by `.outliner-lines`. No CM6 change, no editor remount — the toggle is live. KNOB: `--outliner-x` (Styles.css) nudges the rail onto the bullet centre; the hairline uses the `--separator-segment` weight, coloured `--label-tertiary` for now (Nathan).
- **defaultIcons override scope.** The DRY hoist (`DEFAULT_ENTITY_ICONS`) repointed every literal to one source. The per-nexus *override* is consumed on the sidebar + banners (store is clean there); the table cells + connection autocomplete resolve the constant default only (threading the override through the hot/parallel-heavy table paths wasn't worth it) — a clean follow-up via `ResolveContext` if wanted.
- **The accent "revert" was not a regression.** `//The Nexus` never had an accent in `settings.json` (no `accent_color`), so React always read the lavender default; the back-compat read is behaviourally identical to the old path. The real gap was the missing write path, which this closes — `personalization.accent: cyan` set on that nexus directly.
- **Still deferred:** the settings-panel UI (E-1), the saved-strip `house` dead-key cleanup (C-4, harmless — homepage renders the profile image), and the Swift-residue sweep (F-4).
