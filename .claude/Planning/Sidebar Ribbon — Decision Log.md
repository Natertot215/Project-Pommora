## Sidebar Ribbon — Decision Log

### Frame

- **Purpose:** Add an Obsidian-like **ribbon** (a fixed icon-width column on the left of the sidebar) that switches what the general sidebar shows, laying the infrastructure for future surface-switching. Experimental, on its own branch.
- **Core Value:** A working sidebar that can *swap its content* between modes via ribbon icons — proving the switching + animation model — without breaking the current filesystem tree.
- **Success Criteria:** Ribbon renders as its own bordered section; clicking a ribbon icon swaps the sidebar content (at minimum Collections ↔ Contexts ↔ Agenda); Homepage stays a selection that leaves the sidebar mode untouched; scroll is physically contained to the content column and never crosses the ribbon border; ribbon icons (minus Homepage) drag-to-order and persist.

### Sources

- [[Sidebar]] — current sidebar spec: Nexus header → Contexts → Collections → user sections; one curated tree; section headings are pure UI; overflow-eclipse on scroll.
- [[Navigation]] — main-pane navigation (Back/Forward + breadcrumb); Navigation Popover is Pending. The ribbon's Nav icon is a placeholder for that future surface.
- [[Agenda]] — Tasks/Events data layer round-trips + indexes but **nothing renders**; no entity can be selected/opened. "Agenda Surfacing" is explicitly Pending. The ribbon's Agenda mode is the *first* Agenda UI, and is experimental/stub.
- [[Configuration]] — `personalization` (per-Nexus, synced, in `.nexus/settings.json`) via one schema + apply-map + generic setter; device-local transient UI state (folds, activeView, view order) lives with the read engine, never synced.
- [[Structure]] — Homepage singleton; the Nexus header is its entry point (selecting it opens Homepage in the main pane).
- `Pommora/src/renderer/src/App.tsx:116-142` — the sidebar mounts inside `<Surface>` as a single scrolling `<nav className="sidebar">`; collapse button + resize strip live here. **Ribbon must be a sibling flex column of the scroll container, not inside it.**
- `Pommora/src/renderer/src/Sidebar/Sidebar.tsx:434-498` — the `<nav>` renders NexusHeader → Contexts section (SectionHeader "Contexts" + 3 TierDisclosures) → Collections section (SectionHeader + CollectionRows) → userSections (each a SectionHeader + CollectionRows), all wrapped in `<SidebarDnd>`.
- `Pommora/src/renderer/src/Sidebar/NexusHeader.tsx:16-91` — profile image + name + subtitle; click selects `{kind:'homepage'}`; right-click photo = crop menu; double-click name/subtitle = inline edit.
- `Pommora/src/renderer/src/store.ts:258-266` — `SelectionState` union routes the **main pane**: `none | homepage | context | collection | set | page`. Ribbon mode is orthogonal to this.
- `Pommora/src/renderer/src/store.ts:290-294` — `sidebarVisible` / `sidebarWidth` chrome state lives on the store; `sidebarWidth` persists to localStorage (device-local).
- `Pommora/src/renderer/src/Sidebar/sidebarDnd.tsx` + `sidebarDndModel.ts` — the PommoraDND sidebar engine: frozen-snapshot gesture machine + `nextOrder`/`slotInGroup` reorder math, committed via `store.mutate`. Reference pattern for ribbon-icon drag-to-order.
- `Pommora/src/renderer/src/Toolbar/Toolbar.tsx:63-67` — Navigation + Settings ALREADY exist as toolbar trio stub buttons. Ribbon Nav/Settings are alternate placements of the same future surfaces, no-ops for now.

### Decisions

#### A — Scope & Framing

- **A-1:** [confirmed] This is **one spec**: the ribbon shell + mode-switching infrastructure + the NexusHeader/Homepage restructure + heading removal + the three mode contents (Collections, Contexts, Agenda).
- **A-3:** [confirmed — re-scoped by review] **Agenda mode renders a real read-only list.** The parse/read logic already exists as `collectAgenda()` (`build.ts:239-284`) — reads `Tasks/`+`Events/` folders, zod-parses, yields `AgendaItemData` (id/title/icon/dueAt/startAt/endAt/tiers). **Correction:** `collectAgenda` lives inside `buildIndex` (the SQLite index builder, OFF the read path), and `readNexus` deliberately **skips** agenda folders (`readNexus.ts:416: if (hasAgendaSidecar) continue`). So this is NOT a free "lift into readNexus" — baking agenda reads into the single tree walk adds per-folder file reads on **every** tree read + watcher push, violating the "never expensive work on every X" rule. **Decision: serve Agenda through a dedicated, lazy `agenda:list` IPC** (a small read handler reusing `collectAgenda`'s logic), invoked **only when Agenda mode is active** — NOT a `NexusTree` field. Keeps the read path clean, agenda cost paid only on demand. Preload bridge + list component as before. (Verified free of ripple: an `agenda` field would've touched `stabilize`/`reconcileSelection`, but the IPC approach avoids the tree entirely; and agenda doesn't route — A-4 — so `reconcileSelection` is untouched regardless.)
- **A-4:** [confirmed] **Boundary — agenda rows don't route.** `SelectionState` (`store.ts:258-266`) has no `task`/`event` kind and no agenda detail view exists. Agenda mode lists real entities but rows are display/highlight-only this pass; an agenda **detail surface** (new SelectionState kind + ContentView + `task`/`event` routing) is a Prospect. Contexts rows, by contrast, DO route — `{kind:'context'}` → `ContextView` already works.
- **A-2:** [confirmed] Experimental — lands on its own branch. Always-on `⌘R` toggle is later scope (Prospect).

#### B — Mode State Model (heavy)

- **B-1:** [confirmed] The ribbon is a **surface launcher**: each icon points at a surface, and surfaces live in different panes. Homepage's surface is the *main pane* (a `selection` — routes it, leaves `sidebarMode` untouched); Collections/Contexts/Agenda's surface *is the sidebar column* (they set `sidebarMode`); Nav/Settings target future glass windows (no-op now).
- **B-5:** [confirmed — build revision] **No active-mode highlight.** Nathan: "remove the highlight." The ribbon shows no visual indicator of the active mode (the content shown IS the indicator). `aria-selected` is kept for accessibility, but there's no highlight fill. (Reverses the earlier "exactly one icon highlights" note.)
- **B-6:** [confirmed — build revision] **Rename-nexus relocates to the homepage banner title.** NexusHeader's title-double-click was the only rename-nexus path. The homepage title already renders in the banner but is deliberately inert (Banner.tsx:47-51, because nexus rename is a folder rename via `renameNexus`, not `submitRename`). Chosen home: make that homepage banner title **double-click → inline edit → `renameNexus`** — the consistent app pattern and exactly where the name now lives ("name lives in the homepage"). Preferred over the photo-menu option (rec a) as more consistent + discoverable. The ribbon photo's right-click keeps the existing Add/Change-Photo menu.
- **B-2:** [confirmed] Last-active `sidebarMode` **persists** across restarts (remembered, not always-boot-to-Collections). Stored in synced `personalization` alongside icon order (one home, DRY). Default when unset = Collections (the filesystem tree).
- **B-3:** [confirmed] Switching mode does **not** touch the main pane — it holds the current selection; the main pane only changes when a row is clicked.
- **B-4:** [confirmed — build revision] A mode switch is an **instant swap — no animation.** The slide was dropped for a cross-fade in design; the built cross-fade read badly ("absolutely terrible") so it was removed entirely — only the active mode renders. The *sidebar collapse* still slides (unchanged). A refined transition is a Prospect, not shipped.

#### C — Ribbon Composition

- **C-1:** [confirmed] Icons: Homepage (pinned top, not orderable) + Navigation, Agenda, Contexts, Collections, Settings (drag-to-order below it). Fixed set for now; add/remove is a Prospect.
- **C-2:** [confirmed] Ribbon icon **order** persists in `personalization` (synced, per-Nexus), mirroring `setPlacement`.
- **C-4:** [confirmed] Ribbon collapses *with* the sidebar (it's part of it). Always-on ribbon surviving collapse = the `⌘R` Prospect.
- **C-3:** [confirmed — revised] NexusHeader dissolves into the ribbon. The nexus **profile photo becomes the Homepage ribbon icon** — top-left, where it sits today, but **sized to match the other ribbon icons**. The nexus **name + subtitle are removed from the sidebar entirely** — there is **no content-column header**. The name belongs to the **Homepage view** (main pane), not the sidebar. The **subtitle is parked** — kept in code with an intent comment so it doesn't read as dead code. (Rendering the nexus name in the Homepage view is a small in-scope addition so the name doesn't vanish from the UI; its exact placement in the homepage is a homepage concern → Figma.)

#### D — Layout & Containment

- **D-1:** [confirmed] The ribbon is **a strip pinned to the left edge that nudges the existing content over — NOT a separate flex pane** (Surface stays as-is, no multi-pane rearchitecture). The one hard structural rule: the strip sits **outside the scrolling `.sidebar` element**, so scroll can neither move it nor slide under it. Cleanest realization: ribbon `position:absolute; left:0; top:0; height:100%` inside `.surface-glass`, with the 2.5px right border, and `.sidebar` gets a left inset (`padding-left`/`margin-left`) = ribbon width so its content starts to the right. That single fact delivers both containment guarantees — horizontal scroll stops at the border and never crosses it, and the ribbon is **vertically pinned** (absolute, doesn't scroll with content). Ribbon tabs start at top, descend downward. (Flex-vs-absolute is a build detail; the point is it's a pinned strip + content inset, not a pane.)
- **D-2:** [confirmed — review-caught] Two non-obvious layout requirements, else silent breaks: (a) `.surface-glass` is `-webkit-app-region: drag` and `.sidebar` resets it to `no-drag` (Sidebar.css:14,30) — **the ribbon strip needs its own `-webkit-app-region: no-drag`**, or every icon click drags the frameless window and drag-to-order can't start; (b) `.sidebar` clears the macOS traffic lights with `padding-top: 46px` (Sidebar.css:32) — the ribbon is *outside* `.sidebar` so it **must replicate that top offset** or its top icon collides with the traffic lights. (The earlier `display:flex` concern is void — D-1 uses a pinned strip + inset, not a flex row.)

#### G — Create-Path Relocation (review-caught, needs Nathan)

- **G-1:** [confirmed] Creation relocates to a **right-click context menu** on the mode's content area — "New Collection" in Collections mode, "New Context" (tier picker) in Contexts mode. No header "+" (the headers are gone). This matches Sidebar.md's "creation is right-click-first" intent AND closes the standing backlog item **"Context sidebar crud — you still can't create a Context via the sidebar"** (Handoff.md:117) in the same move. `newCollection`/`newContext` (currently `popCreateMenu`, Sidebar.tsx:409,466) rewire to the right-click handler.

#### F — Don't-Forget Sweep (structural + interactive)

- **F-1:** [confirmed] **Chrome coexistence** — the collapse button (Surface top-right), expand button (top-left, shown collapsed), and right-edge resize strip must still work with the ribbon present. Ribbon is leftmost; resize strip stays at the content's right edge; on collapse the whole unit (ribbon + content) slides off together (C-4). Layout check at build.
- **F-2:** [confirmed] **DnD isolation** — ribbon icon drag-to-order is a *separate* PommoraDND zone from the sidebar tree DnD; the two gestures must not cross-target. The ribbon zone reorders a flat icon list only.
- **F-7:** [confirmed — review-caught] **The tree DnD wrapper splits.** Today Contexts + Collections share a single `<SidebarDnd>` (Sidebar.tsx:443-496). Mode-split renders them in separate columns, so that one wrapper becomes **two `<SidebarDnd>` instances** (one per mode), each over its slice of the tree (`buildIndex` tolerates a partial tree). Note the transient double-mount during the ~380ms cross-fade — survivable (separate instances/`rows` maps), but the plan must not assume one wrapper.
- **F-3:** [confirmed] **Empty states** — each mode handles empty gracefully: Agenda with no tasks/events, Contexts with no tiers populated, Collections already handled. No mode renders a broken/blank column.
- **F-4:** [confirmed] **Live watcher reconciliation** — if agenda files (or the active mode's data) change on disk, the mode re-reads on the watcher push without stranding. Agenda list re-reads from its IPC/tree field on refresh.
- **F-5:** [confirmed] **Persistence back-compat** — new `personalization` keys (`sidebarMode`, ribbon order) follow the existing discipline: unrecognized keys preserved by value, absent keys fall back (mode→Collections, order→default seed). An old `settings.json` reads clean, no migration.
- **F-6:** [confirmed] **No content-column header at all.** Modes are header-less — the ribbon tab IS the label (Collections/Contexts/Agenda are sidebar/window openers, not views that need a title). The content column starts straight into its mode content. The nexus name lives in the Homepage view, not here (C-3).

#### E — Heading Removal & Reconciliation

- **E-1:** [confirmed] Remove the "Contexts" and "Collections" SectionHeaders (the ribbon tab is now the label). **User-section headings stay** within Collections mode (they're user-named groups, not chrome).
- **E-3:** [confirmed] **User sections are read-only orphans** — `readNexus.ts:374,427-436` reads them from the `.nexus/` sidebar-sections config (`{id,label,collectionIDs}`), but `mutate.ts:37-76` has **zero section ops** (no create/rename/delete/assign) and there's no right-click/"+" to make one. Nathan confirmed this needs fixing, but **split into its own spec (`User Sections CRUD`), sequenced AFTER the ribbon** — "go for the ribbon first." Out of scope for this spec; noted so the next spec picks it up. The ribbon's SectionHeader rework must not foreclose adding a section-create affordance later.
- **E-2:** [confirmed] Reconciliation map — these go partially false and must be updated with the code:
  - **Sidebar.md** — the whole "top to bottom: Nexus header → Contexts → Collections → user sections" framing is replaced by ribbon + modes; section-heading rows for Contexts/Collections removed; the "Calendar Pin" Pending item becomes the shipped Agenda mode (read-only list).
  - **Structure.md** — "The Nexus header at the top of the sidebar is its [Homepage] entry point" → the Homepage *ribbon icon* is now the entry point; name/subtitle relocation noted.
  - **Agenda.md** — "Agenda Surfacing … nothing renders" Pending item narrows: a read-only sidebar list now renders; detail/interactivity stays Pending.
  - **Navigation.md** — the ribbon's Navigation icon is another placeholder for the Pending Navigation Popover (alongside the toolbar trio button).
  - **Configuration.md** — `personalization` gains `sidebarMode` + ribbon icon order knobs (new apply-map rows / read-coerced fields).
- **E-4:** [confirmed] `sidebarMode` + ribbon order are new `Personalization` fields (`src/shared/types.ts`) — read-coerced in `readNexus.ts` and written via the existing `setPersonalization` generic setter + IPC. No new write plumbing beyond schema fields (mirrors `favoriteIcons`/`setPlacement`). Agenda list needs its own read path + IPC (A-3).

### Core (must-have)

1. **Ribbon shell** — a fixed-width icon column, a sibling of the scrolling `<nav>` inside `<Surface>`, with a 2.5px right border; vertically pinned (never scrolls with content) and horizontally uncrossable by the content's scroll. Collapses/expands *with* the sidebar.
2. **Ribbon icons** — Homepage (pinned top) + Navigation, Agenda, Contexts, Collections, Settings below it. Exactly one shows the active-mode highlight (= current `sidebarMode`); Homepage never highlights.
3. **`sidebarMode` state** — new store field, orthogonal to `selection`. Mode-switch icons (Collections/Contexts/Agenda) set it; it persists in synced `personalization` (default Collections). Nav/Settings no-op. Homepage dispatches `select({kind:'homepage'})` and leaves the mode untouched.
4. **Content column = mode switch** — renders per `sidebarMode`, cross-fading between modes via `useExitPresence` (opacity, no slide). Each mode owns its scroll container.
   - **Collections mode:** the current filesystem tree (Collections + user sections), minus the "Collections" SectionHeader; user-section headings kept. Right-click → "New Collection" (G-1).
   - **Contexts mode:** the three tiers relocated out of the current Contexts section (headers removed); rows already route via `{kind:'context'}` → `ContextView`. Right-click → "New Context" (G-1, closes Handoff.md:117).
   - **Agenda mode:** a real read-only list of Tasks + Events via a lazy `agenda:list` IPC (A-3); rows display/highlight-only (no routing — A-4).
5. **NexusHeader dissolves** — profile photo → the Homepage ribbon icon (top-left, sized to the ribbon icons); nexus name + subtitle removed from the sidebar; no content-column header; subtitle parked with an intent comment; nexus name rendered in the Homepage view instead (C-3, F-6).
6. **Ribbon icon drag-to-order** — Homepage fixed; the rest reorder via the PommoraDND pattern, order persisted in synced `personalization`.
7. **Docs reconciled** — Sidebar.md, Structure.md, Agenda.md, Navigation.md, Configuration.md (see E-2 / reconciliation below).

#### Prospects (allowed later, not now)

- Always-on ribbon + `⌘R` toggle.
- Contexts as a glass popover surface (this spec puts it *in* the sidebar temporarily to test swapping).
- Nav / Settings / Contexts as glass surface windows.
- User add/remove of ribbon icons.
- **Agenda detail + interactivity** — a `task`/`event` SelectionState kind, an agenda ContentView, row→main-pane routing, calendar/date-grouped layouts, create/edit. This pass ships the read-only *list* only.
- Agenda list backed by the SQLite index (date-range queries, filters/sorts) — the file-walk read path suffices for a flat list now.
- **User Sections CRUD** (E-3) — its own spec sequenced AFTER this one: section create/rename/delete mutate ops + IPC + right-click "New Section" + drag-collection-into-section. Don't-foreclose: the ribbon's SectionHeader rework must leave room for a section-create affordance.
- Per-mode content-column header treatment (a mode title vs just the nexus name).

#### Out of Scope

- Building the actual Navigation Popover or Settings editor surfaces (this only places placeholder icons).

#### Considered & Rejected

- **Reuse `PaneSlider` for mode-switching** — rejected: it's a binary root↔detail slider that animates *height* and is built for capped dropdown panes with pinned footers (ResizeObserver + MenuScrollFrame); it would fight a full-height scrolling column. (Then the whole slide idea was dropped for a fade — B-4.)
- **A dedicated full-height slide-slider** (cross-slide via translateX) — considered as the honest read of "same slide the sidebar uses," rejected by Nathan in favor of a cross-fade (less layout-jank risk on two independently-scrolling columns).
- **Ribbon icons as three special-case behavior classes** — reframed (not rejected) into the cleaner "surface launcher" model (B-1): one concept, surfaces just live in different panes.
- **Bundling User Sections CRUD into this spec** — rejected: independent subsystem, split to its own spec, ribbon first (E-3).
- **Agenda mode as a pure stub** — rejected once verified cheap: it ships a real read-only list instead (A-3).

#### Lessons

- "Same as the current X" is a hypothesis about the code, not a spec: the sidebar had *two* slide primitives (PaneSlider, the collapse translateX) and neither was a clean fit — grounding the motion choice mattered as much as grounding the data.
- A feature can be "in the read path" yet completely unreachable: user sections read fine but had zero write ops — "it displays" ≠ "you can make one." Check the mutate op list, not just the reader.
- `readNexus` (read path) and `buildIndex` (SQLite index) are two separate walks on opposite sides of a hard boundary. Reusable *logic* in the index builder isn't a free lift into the read path — moving it there adds cost to "every X." Reuse the logic via a lazy on-demand IPC, not the tree walk.
- Frameless-window chrome bites silently: `-webkit-app-region: drag` on `.surface-glass` + the `no-drag`/`padding-top:46px` resets on `.sidebar` mean any new sibling of `.sidebar` must re-declare both, or clicks drag the window and content hits the traffic lights.
- Removing a UI heading can remove the only affordance behind it: the Contexts/Collections "+" were the sole create path. "Remove the header" silently means "remove creation" unless the action relocates.
