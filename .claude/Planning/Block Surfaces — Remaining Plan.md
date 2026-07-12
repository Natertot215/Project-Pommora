## Block Surfaces — Remaining Implementation Plan

The forward plan for the Block Surfaces arc after the H-5 chrome + scroll model shipped. The spec is the certified `7-10 - Block Surfaces — Decision Log.md`; this breaks the remaining work into ordered, independently-shippable tasks with the five just-ratified decisions baked in. Each task re-grounds its exact `file:line` seams at pickup (Studio discipline) — the paths below are verified current, not line-pinned.

### Settled Decisions (baked in)

- **Locked page embed keeps its open action** (H-3) — a lock guards content, never navigation.
- **The view-embed settings footer lock IS the B-5 per-tile config lock** — freezes that one embed's config, nothing wider.
- **Per-view source re-pointing is parked** (Prospects) — an embed's source is fixed at pick; re-point = delete + re-insert for now.
- **Edge-release scroll works as-is** — the hover-intent escalation stays documented-but-unbuilt.
- **Page recents are shared architecture** — one `state.json` session-state record, read by the Link Page pane, Navigation, and any future consumer; whoever builds first lays it.

### Order & Rationale

1. **Task 5 — Link graph** first: small, isolated, closes the read/index plumbing.
2. **Locks** next: self-contained, and it's what turns the settings surface from decorative into functional. All three tiers' decisions are settled.
3. **Insert menu + Link Page search (with the shared recents) + page-embed header**: chrome, reusing the shipped picker; the recents record built here (Navigation adopts later, per the shared-architecture call — so this arc no longer waits on Navigation).

Interaction foolproofing runs with Nathan's hands alongside all of it.

---

### Task 5 — Link Graph Host Passes

**What it does (plain):** a `[[Some Page]]` written inside a markdown block currently renders as a link but is invisible to the connections index, and renaming "Some Page" leaves the block's link text stale. This makes block links first-class — indexed as real link sources, and healed on rename.

**Seams:**
- `src/main/connections/scan.ts` — scans page bodies for `[[links]]` into edges. Extend to also walk markdown-block bodies (`.nexus/<host>/<tile-ulid>.md`, enumerated from each host's `blocks[]`).
- `src/main/connections/rewrite.ts` — the `[[Title]]` rewrite primitive.
- `src/main/crud/cascade.ts` (`renameCascade`, invoked at `mutate.ts:191`) — rewrites inbound links nexus-wide on a page rename.

**Approach:** block `.md` files are **id-less** (`<ulid>.md`, not page-graph members), so they can't ride `renameCascade`'s page walk — a **dedicated block-body pass** scans + rewrites them, reusing the `connections/rewrite.ts` primitive. The pass runs alongside `renameCascade` (same rename transaction) so a rename heals pages and blocks atomically. Index side: `scan.ts` emits block-sourced edges so backlinks see them.

**Gate:** unit tests (a block body with `[[X]]` indexes as an edge from that block; renaming X rewrites the block body; a locked/pending block flush doesn't clobber — the file lock at `blocks.ts:197` already guards this) → `npm run typecheck` + `vitest`.

---

### Task 6.1 — Locks (three tiers)

**What it does (plain):** nothing is lockable yet. Three independent locks, each persisted to its entity's sidecar (synced, never per-machine), each on the same **configure-vs-interact** line.

**Tier A — Host lock (G-3):** freezes the whole board (no tile drag/resize).
- Seams: `blocks_locked` already round-trips in `main/blocks.ts` (read as `doc.locked`); wire a `static`-style prop through `SurfaceView`/`BlockSurface` that gates every gesture (drag, resize, background-create), and the host SettingsPane's footing lock toggle.

**Tier B — Per-tile lock (B-5):** locks one embed.
- Page tile locked → no edit, no click-into-body; **open action stays** (H-3). View tile locked → config frozen, interaction (data drags, value edits) live.
- Seams: a per-tile `locked` key on the entry; the **view-embed settings footer lock** (currently drawn inert in `SettingsPane.tsx`) writes it — this is the B-5 lock. The tile consumes it kind-specifically in `MarkdownBlock`/`PageEmbedBlock`/`ViewEmbedBlock`.

**Tier C — Container view-lock (G-5):** locks a Collection/Set's views everywhere (not just embeds).
- Seams: a lock in `Toolbar/ViewPane.tsx`'s `MenuBottomRow`; when engaged, dims the SettingsPane + ViewPanes container-wide (config + view CRUD disabled); persists in the container's sidecar. **Standalone-buildable** — doesn't depend on the block system, so it can split to its own commit.

**Gate:** each tier's gating verified live (locked host can't drag; locked page can't edit but opens; locked view freezes config, drags live; locked container dims its panes) + main-side sidecar round-trip tests.

---

### Task 6.2 — Insert Menu (G-9)

**What it does (plain):** right-clicking the empty homepage background drops a markdown block today. Upgrade it to a **Page / View / Block** choice through the same picker the drag handle uses.

**Seams:**
- `src/renderer/src/Blocks/BlockSurface.tsx` — `onBackdrop` (the current direct-create) and the shipped `pagePickerItems`/`viewPickerItems` + `applyPagePick`/`applyViewPick` (the drill trees already built for the handle menu).
- `BlockHandleMenu.tsx` / `PickerMenu` — the picker shell to reuse.

**Approach:** the background right-click opens the picker at the click point with a root of **Page** (→ the Link Page search pane, Task 6.3) · **View** (→ the existing source drill: Collections → Sets chevron → views, + Custom footer) · **Block** (→ the current `createMarkdown`). The wedge/append target resolution (`onBackdrop`'s `BackdropTarget`) is already built and unchanged — only the create step gains the menu in front of it.

**Gate:** each path creates the right tile at the right target (wedge vs append) + the picker flows verified live.

---

### Task 6.3 — Link Page Search Pane + Shared Recents

**What it does (plain):** embedding a page (via Insert → Page, or the handle's Link Page) opens a search — type to filter, results as icon + title over the `Collection › Set` path, recently-opened pages first until you type.

**Seams:**
- **Shared recents record** — `.nexus/state.json` session-state, read/written like `crud/reorder.ts`'s top-level orders. A capped, ordered list of recently-opened page ids, appended on page open (the page-open path in the renderer/store). Built here as the **shared** record (Navigation adopts it, per the ratified call) — NOT a Link-Page-local list. (`appConfig.recents` is nexus-level and unrelated.)
- **The search pane** — a `PickerMenu`-hosted scrolling search over all Collections' pages; result rows reuse the menu row + path breadcrumb tone; recents-descending seed until the query is non-empty.

**Approach:** build the recents record + its narrow IPC first (append-on-open + read), then the pane consumes it. The pane resolves a `page_id` and hands it to `applyPagePick` (Task 6.2's flow) — so Insert → Page and the handle's Link Page share one pane.

**Gate:** recents round-trip (open pages, they surface newest-first) + typed search filters + a pick resolves the embed. Shared-record test so Navigation can rely on the same shape.

---

### Task 6.4 — Page-Embed Header

**What it does (plain):** the view-embed header is done; the page-embed still needs its hover ⋮ menu with the banner/title toggles.

**Seams:** `src/renderer/src/Blocks/PageEmbedBlock.tsx` — the `banner`/`title` boolean fields on `PageBlockEntry` are already wired in the schema; add the top-right hover ⋮ (the G-4 chrome family) opening a small menu that toggles them + `display_title`. Mirrors the view-embed's title-row menu pattern.

**Gate:** toggles flip the page-embed banner/title live + persist on the entry.

---

### Verification Discipline

Per task: design disclosure (disclose-before or screenshot-after, never neither) → gates (`npm run typecheck` + `vitest` from `Pommora/`) → build-breaking-agent review, findings verified first-hand → fold → commit. Re-ground each task's cited seams before writing its code. Post-functional UIX review closes each visible surface.
