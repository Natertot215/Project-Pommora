## Handoff — Pommora React

> ⚡ **Cornerstone — carry into every handoff, unchanged (Nathan's voice).**
> *"You do NOT guess — you LOOK, and you ASK. Open the file and read the code before you assert anything; ask me when you're unsure. A plan built on an unverified claim is a liability, not progress — treat every doc, every `file:line`, every 'it works like X' as a hypothesis until you've read the code that proves it. Honesty over confidence; confidence is earned through evidence."*

### Recent Work

Prior arcs, compressed — the detail lives in `Features/*` + `History.md`.

- **PropertiesV2 — the nexus-wide registry.** Definitions live in `.nexus/properties.json` (`{order, defs}`); a Collection's sidecar holds only its assignment-id array; `readNexus` joins the two so every surface gets a resolved schema. Registry mutations serialize; SQLite mirrors it as a regeneratable accelerator.

- **Tables cell + group system (Phases 1-3).** The full cell-gesture matrix (title navigates · status/select/multi/context open the PickerMenu · numbers inline-edit · urls/files open through IPC · right-click always menus). Per-view looks/formats persist in the SavedView's `column_styles`. Group bands drag to reorder; the reusable editing surfaces live table-agnostic in `Detail/Views/PropertyEditing/`. → `Features/TableView.md`.

- **Status + Link/URL property panes.** Status: an open group model (stable-id groups, value=title cascade, in-place grouped editor). Link/URL: `resolveFieldValue` coerces plain-string kinds to the DECLARED type post-cache; `link-title` fetches the page `<title>` (main owns `net` + `.nexus/linkTitles.json`); alias always wins, stored `[alias](url)`. → `Features/Properties.md`.

- **Multi-View Scaffolding + the per-type property editors.** The per-container view switcher stack (ViewDropdown · ViewPane→SettingsPane rename · two-door ViewSettings), the **G-1 invariant** (views never empty where views can be seen — creation-seed + entry-mint, adopt-only through `saveViewAdopting`), and the Date & Time · Checkbox · Number editor panes (def-level config via registry IPC, per-view look via `column_styles`). Only the relation/context pickers remain. → `Views.md` + `Properties.md` + `History.md`.

- **Mobile iOS companion (parked).** A ratified **Capacitor** spec under `.claude/Mobile/`; a scoped port, 4 desktop pre-paves shipped (`02bb4e11`). No build commitment.

### Session Summary — Icon Picker + the Sidebar Ribbon Rework (Both Shipped)

**Session ID:** c3e6af60-f1ea-4e19-9507-08776f15d04a
**Dates:** 07-05 → 07-08-2026
**Model:** Opus 4.8
**Compactions:** 7
**Connectors:** none (CDP WORKS this arc — Nathan runs his own dev on `--remote-debugging-port=9222`; Claude drives it for verification, Nathan is the live eyes too)
**Commands:** /compact · /handoff
**Agents:** Explore (7x - grounding), build-breaking-agent (4x - spec + fix review), code-simplifier (3x - cleanup)
**Skills:** studio-brainstorm · `superpowers:writing-plans` · `superpowers:executing-plans` · handoff

Two arcs past the property editors: the **Icon Picker** (full-lucide picker, wired app-wide, on main) and the **Sidebar Ribbon** (an Obsidian-style rework on its own experimental branch — the whole latest session). Both shipped; the ribbon lives unpushed on `sidebar-ribbon` pending Nathan's merge call. The property-editor arc it followed is compressed into Recent Work above.

**Icon Picker built + wired (`e6e1a7e0`→`7559bd9e`, on main).** The stubbed IconPicker became the real picker: a left-aligned non-autofocus search over the ENTIRE Lucide set (`design-system/symbols/AllSymbols`, ~1,715 icons kebab-keyed, TanStack-virtualized) in `label-control`, a right-click native **Favorite** menu (`iconFavoriteMenu.ts`, mirrors `popOptionMenu`), and a drag-reorder favorites box scrolling WITH the grid under one `overflow-eclipse`. The container moved to the shared **PickerMenu**, which grew a horizontal beak + `center` straddle + `bareSurface` + auto-flip. **Locked — one shared `setIcon` write:** all six edit-icon sites wired (page/container/context via one `setIcon` mutate op dispatched by kind, property via `property:setIcon`, view via `views.save`); the `Icon` render path resolves any id (curated → full set → dashed-square) and became a `forwardRef` so the glyph element IS the picker's `triggerRef` (the beak anchors to the icon). → `Icons.md` + `Interaction.md` + `History.md`.

**Sidebar Ribbon — brainstorm → plan → inline-build (branch `sidebar-ribbon`, NOT pushed).** The single-tree sidebar became a **ribbon + mode-switched content column**. **Locked — surface-launcher model:** each ribbon icon points at a surface in a different pane — Homepage (the profile photo, pinned top) is a *selection* that routes the main pane and never changes the mode; Collections/Contexts/Agenda switch a new `personalization.sidebarMode`; Nav/Settings are inert future-window placeholders. Icons drag-to-order (`ribbonOrder`, synced). **Locked — mode swap is instant, no animation** (the cross-fade was built and cut: "absolutely terrible"). **Locked — Agenda surfaces read-only via a lazy `agenda:list` IPC kept OFF the tree walk** (reuses the index builder's collect logic in a lean sibling — folding it into `readNexus` would break "never expensive on every X"); rows display-only, no agenda SelectionState kind. **NexusHeader dissolved:** photo → the Homepage ribbon icon (`NexusPhoto`), name + rename → the homepage banner title (double-click → `renameNexus`, previously inert), subtitle parked. Section headings gone (the ribbon tab is the label) → creation moved to **right-click the empty mode area** for a native New Collection / New Context menu — which closes the old "can't create a Context via the sidebar" gap. One adversarial round (5 findings, all folded: the window-drag inheritance, the readNexus↔buildIndex boundary, the vanished create path). → `Sidebar.md` (redone canonical) + `Structure`/`Agenda`/`Navigation`/`Configuration` + `History.md`; decision log + plan in `Planning/`.

**The critical live bug: the nav ate every ribbon click (`f569bf7d`).** After build Nathan hit "clicking out [of a mode] is impossible" — CDP proved the ribbon got ZERO pointer events. The `.sidebar` nav used left-**padding** to clear the ribbon, so its element spanned UNDER the ribbon's strip and won hit-testing (`elementFromPoint` returned the nav, not the button); `z-index: 0` doesn't lift a positioned element above a same-context sibling here. Fix: left-**margin**, so the nav + ribbon are physically disjoint (robust, z-index-independent). The bug had shipped since the ribbon's first build; it only surfaced once a persisted `sidebarMode: 'agenda'` parked Nathan in an empty Agenda mode with no way to click back — a trap sharpened by his removing the active-mode highlight (an empty highlightless mode reads as "broken sidebar").

**The hide-chevron fill-inset loop (Nathan-driven).** He tested `hideChevrons` live (persisted TRUE to his settings — likes it, kept), then wanted the selection fill inset off the ribbon WITHOUT moving the icon/title, then its ribbon-side corner to round. First pass insetted via a transparent `border-left` + `background-clip: padding-box` — which SQUASHED that corner (border-radius reduces per-corner by the border width). Redone with a plain `margin-left` (fill keeps full 8px rounding), absorbing the shift in the chevron slot's negative margin so content stays put. Knob: `--sidebar-hidechevron-pad`.

### Lessons Learned

- **A nav that clears a sibling with PADDING still spans under it and wins hit-testing.** The sidebar used `padding-left: ribbon-w` to inset content past the ribbon, so the nav *element* still covered the ribbon's strip and `elementFromPoint` returned the nav — every ribbon click hit the invisible nav, not the icon. `z-index` didn't save it (a positioned `z-index:0` vs a same-parent static sibling). Use `margin` so the two are physically disjoint; overlap + z-index is the fragile version.

- **A transparent border insets a fill but SQUASHES that corner's radius.** `border-radius` reduces per-corner by the adjacent border widths, so a `border-left` for a left inset flattens the fill's left corners to near-square. To inset a rounded fill and keep the radius, use `margin` (outside the border box) — the fill's own corners stay at full radius.

- **`readNexus` (read path) and `buildIndex` (SQLite) are separate walks across a hard boundary.** Reusable *logic* in the index builder is NOT a free lift into the read path — moving it there adds cost to "every X." Reuse the logic via a lazy, on-demand IPC (Agenda's `agenda:list`), not the tree walk.

- **"Add a heading" looked like one line; it's a whole CRUD.** A sidebar heading (user section) is only useful once you can create + rename + drag Collections under it — the deferred User Sections spec. A create-only stub (an empty, unrenameable heading) would be worse than nothing. Don't half-build a menu item whose feature is deferred.

- **A persisted view-mode is a trap when a mode can be empty + unlabeled.** `sidebarMode` persists (Nathan's call), so an accidental switch to an empty Agenda mode — with the active-mode highlight removed — booted him into what read as a broken sidebar with no visible way out. Persist-last-mode is fine; the guardrail is that no mode should be indistinguishable from "broken."

### Next Session

**1. The last per-type property editor: the relation (context) pickers.** Date & Time, Checkbox, and Number shipped; only the context/relation pickers remain per Properties.md Pending. The `NumberEditor`/`DateTimeEditor`/`CheckboxEditor` trio + the shared `PickerControl` + the `saveColumnStyle` (per-view) / batched-IPC (def-level) split in `PropertiesPane.tsx` are the pattern to mirror.

**2. The remaining multi-view stubs** — the non-Table renderers (Cards · List · Gallery · Calendar · Timeline; the `PropertyEditing/` surfaces are table-agnostic for reuse) and the ViewSettings Group · Sort · Filter leaves (blank-leafed; wire to `GroupConfig`/`SortCriterion[]`/`FilterGroup`). The Number editor's parked **Ring + tile-grid Show-as** is the natural first per-view-look add when a vertical-room view lands.

**3. User Sections CRUD** — the deferred "Add Heading" feature (see Pending Focuses) is the natural next piece of the sidebar arc if Nathan wants to continue it.

### Pending Focuses

- **User Sections CRUD (the "Add Heading" feature).** Collections can *render* user-created sections but there's no way to *make* one (read-only orphans; `mutate.ts` has zero section ops). The spec: an "Add Heading" entry on the Collections right-click menu (currently a single "New Collection"), section rename, and drag-a-Collection-into-a-section. Its own brainstorm→plan→build; the ribbon decision log already parks it in Prospects. → `Sidebar.md` Pending.

- **`hideChevrons` is now TRUE in Nathan's REAL `.nexus/settings.json`** (he flipped it live this session, likes it, keeping it). Revertible by setting it `false`. The whole ribbon itself is the `sidebar-ribbon` branch — the revert unit if the rework is ever backed out.

- **The dropdown row-title tone is `label.primary`** (`menuSurface.css` `.surface .titleText`). Load-bearing for the Properties-pane tone hierarchy — the unassigned-row `0-3-0` override assumes it. Don't flip it back to `label.control` without re-checking the tiering.

- **(Perf) Standing debt:** (1) no row virtualization — every row MOUNTS, bites at thousands. (2) External VALUE edits don't live-refresh an open table (`loadValues` runs per container-open). Container-surgical reconcile is the designed escalation at real scale.

- **Number editor eyeball items (Nathan may tune, not bugs):** Decimals "Hidden" (display-as-integer), fraction wording ("N out of M" vs "N/M"), bar clamp at the `>100%`/zero-divisor edges, the strokeless bar look, field widths. Knobs in `numberEditor.css.ts` / `textPicker.css.ts` / `formatValue.ts`.

- **Add-to-group:** the `+` glyph beside a set's grouping label creates nothing.

- **Canvas** — spec at `Planning/6-26 - Canvas Spec.md`, pending adversarial review → plan → build.

- **Biome config vs code** — `biome.json` declares double-quote/organizeImports but the codebase is single-quote/no-semicolon. Settle once, in a tree with no parallel edits.

- **Automatic Scrolling** — must-have for views + MarkdownPM.

- **iCloud-sync readiness (future):** in-process `serializeOnFile` can't coordinate with the iCloud daemon — cross-device is last-writer-wins. `.nexus/index.db` needs sync-exclusion; the walk must skip `.icloud` placeholders.

- **Mobile iOS companion (parked):** spec at `.claude/Mobile/MobileSpec.md`; step 1 is a `window.nexus` bridge shim + a native iCloud Swift plugin. No build commitment.

### Fix Log

- **`.nexus/activeViews.json` + per-machine siblings aren't gitignored (live).** Neither it nor `folds`/`viewOrders`/`tableHeadingColumns`/`linkTitles` are ignored — using the switcher on a fresh container creates a would-sync file. Add to the Nexus `.gitignore` (or scaffold it).

- **The "File" property icon gets clipped** by its vertical row padding on the ViewPane.

- **The link rename field shows a leading empty space (DEPRIORITIZED).** A visual inset, not a stored/typed char (frontmatter clean, survives backspace). Likeliest: `TextPicker`'s left padding or `nativeCaret`'s position-only blind spot. Log it, don't chase it.

- **Block-math `$$…blank…$$` drag corrupts the doc (open).** A multi-line block-math span with a blank line parses as two halves with orphaned `$$`; block-dragging either corrupts the doc (`MarkdownPM/editor/blockModel.ts`, test-pinned, unguarded).

- **Bullet single-word wrap drops the word below the marker** — only the `line-height` cap shipped. → `Features/MarkdownPM.md`.

### Working Notes

- **UI iteration runs in dev mode (HMR)** — CSS hot-swaps, React Fast-Refreshes, but **CM6 extension code needs ⌘R**, and **`src/main`/preload need a dev-server restart** (a new native menu / IPC won't appear until then — bit the ribbon's `agenda:list` this session). Nathan runs his own `env -u ELECTRON_RUN_AS_NODE npm run dev`.

- **HMR is NOT trustworthy for two classes:** (1) vanilla-extract `*.css.ts` — a style edit can serve stale compiled CSS; a plain restart heals it, ⌘R never does. (2) A component's focus effect / handler / attribute change — Fast-Refresh often skips it. Full kill + relaunch before concluding a CSS-in-TS or handler change failed. (Plain `.css` like `Sidebar.css` DOES HMR reliably.)

- **The dev app runs against Nathan's REAL Nexus.** UI value writes are his data; CDP must open + Esc only, never pick/commit — unless he authorizes a mutating gesture. **CDP works:** launch `env -u ELECTRON_RUN_AS_NODE npm run dev -- --remote-debugging-port=9222`, drive via a small Node built-in-`WebSocket` CDP client (`Input.dispatchMouseEvent` for real trusted clicks — synthetic React events don't fire onClick; `getBoundingClientRect` gives CSS coords = CDP coords; `elementFromPoint` to find what's actually on top; `Page.captureScreenshot` → Read the PNG). **Native OS menus don't render in the DOM — CDP can't drive or screenshot them;** reach those ops through `window.nexus.*` IPC via `Runtime.evaluate`.

- **Gates:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (two passes, the ONLY type gate) + `npx vitest run` + `env -u ELECTRON_RUN_AS_NODE npm run build`. Biome auto-formats on write — never run it, never hand-align.

- **Parallel sessions / edits** — stage explicit paths, never `-A`. Nathan tunes knobs (colors, spacing px) in his own editor alongside Claude — unattributed `M` files are almost always his, left uncommitted on purpose; fold them into the related commit when he says so.

### Handoff Rules

- **Never record a correction-to-obvious as a discovery.** Write the durable truth as if always so; silently fix what contradicts it. A fresh agent shouldn't be able to tell a mistake was made.

- **Resolve = delete + route, never tag.** When an entry's done, push its outcome to the canonical doc and delete the line — no `(Resolved)` tombstones.

- **One block per session, updated in place.** Compactions bump the count, they don't add sections. Carry still-open Pending + Fix Log to a fresh session.

- **Markdown only, no new folder** (per Nathan) — this stays the single `.claude/Handoff.md`, not a routed `Handoffs/` dir.

- **Parallel sessions share this one doc** — a concurrent session adds its own labeled block; Cornerstone + footer shared; never edit another session's block.
