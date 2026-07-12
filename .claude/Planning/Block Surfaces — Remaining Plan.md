## Block Surfaces — Remaining Implementation Plan

The forward plan for the Block Surfaces arc after the H-5 chrome + scroll model shipped. The spec is the certified `7-10 - Block Surfaces — Decision Log.md`; this breaks the remaining work into ordered, independently-shippable tasks with the five just-ratified decisions baked in. Each task re-grounds its exact `file:line` seams at pickup (Studio discipline) — the paths below are verified current, not line-pinned. **Review-hardened:** one adversarial plan-review pass grounded every named seam against the real code — corrected the link-index walk site (`index/build.ts`, not `scan.ts`), the block-edge insert (`replaceConnections` hardcodes `source_kind: 'page'`), the state.json concurrency gap, and the page-embed field set (no `display_title`); all five ratified decisions verified honored.

### Status

- **Task 5 — Link graph: SHIPPED + review-certified** (`12e023a3` + `fb6604a0`). Block `[[links]]` index as block-source edges; a page rename heals block bodies beside `renameCascade`. Folded review findings: the build walk reads config directly (read-only), mtime-safe listing.
- **Task 6.1 Tier B (view-embed config lock): SHIPPED** (`5c6cc101`). Nathan's call: the lock lives in the **SettingsPane footer, no dimming**. It freezes the view config via the single `persistConfig` chokepoint (every leaf pane + header routes through it) + guards view CRUD; `setLocked` writes the entry directly so you can always unlock. `locked?` rides `ViewBlockEntry`.
- **Bracket bug fixed at source** (`704344ea`, outside this plan): `pageLinkPattern` now tolerates internal brackets in a title — repairs page + block bodies at once; names with brackets stay legal.
- **Remaining is design-gated** — the calls Nathan still owns are folded into each task below.

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
- `src/main/index/build.ts` (the `for (const p of data.pages)` walk that calls `connectionEdges(p.id, p.body, linkIndex)` then `replaceConnections(db, p.id, conns)`) — this, **not `scan.ts`**, is where edges are built. Add a **host-folder pass** here that reads each `.nexus/<host>/<tile-ulid>.md` (enumerated from each host's `blocks[]`) and builds edges from block bodies.
- `src/main/connections/scan.ts` (`scanConnections`, **pure — no I/O**) + `src/main/connections/edges.ts` (`connectionEdges`) — the per-body primitives the block pass reuses; they walk nothing themselves.
- `src/main/index/upsert.ts` — `replaceConnections` **hardcodes `source_kind: 'page'`**, so block edges need a **separate insert** with a block source_kind (the `connections` schema already carries `source_kind`/`surface` columns, `index/schema.ts`, no FK — a block-sourced row is legal).
- `src/main/crud/cascade.ts` (`renameCascade`, invoked at `mutate.ts:191`) + `src/main/connections/rewrite.ts` (`rewriteConnections`) — the rename heal.

**Approach:** block `.md` files are **id-less AND `.nexus`-resident**, and `renameCascade` both requires a frontmatter `id` and skips `.nexus` — either gate excludes blocks by design, so extending it would compromise its page-only id gate. A **dedicated block-body rewrite pass** (reusing `rewriteConnections`) runs beside the page cascade in the same rename call (`mutate.ts:191`), **best-effort and per-file-locked** — `renameCascade` is re-runnable, not cross-file atomic, so a block-pass failure leaves pages healed + blocks stale (recovered by re-running); it must not leave the page rename un-revertable. Index side: the `build.ts` host-folder pass emits block-sourced edges so backlinks see them.

**Gate:** unit tests (a block body with `[[X]]` indexes as a **block-source** edge; renaming X rewrites the block body; the file lock at `blocks.ts:197` guards a pending editor flush) → `npm run typecheck` + `vitest`.

---

### Task 6.1 — Locks (three tiers)

**What it does (plain):** nothing is lockable yet. Three independent locks, each persisted to its entity's sidecar (synced, never per-machine), each on the same **configure-vs-interact** line.

**Tier A — Host lock (G-3):** freezes the whole board (no tile drag/resize), and — per G-14 — **pins the borderless chassis hidden** (a locked host never reveals a tile's border/handle on hover).
- Seams: `blocks_locked` already round-trips in `main/blocks.ts` (read as `doc.locked`, reaching the renderer via `useBlockDoc`); wire a `static`-style prop through `SurfaceView`/`BlockSurface` that gates every gesture (drag, resize, background-create) + the borderless reveal, and the host SettingsPane's footing lock toggle.

**Tier B — Per-tile lock (B-5):** locks one embed (**embeds only** — markdown tiles have no per-tile lock; they're covered by Tier A's host lock).
- Page tile locked → no edit, no click-into-body; **open action stays** (H-3). View tile locked → config frozen, interaction (data drags, value edits) live.
- Seams: a per-tile `locked` key on the entry; the **view-embed settings footer lock** (currently drawn inert in `SettingsPane.tsx`, an `onClick={()=>{}}` with an "inert until locks" comment) writes it — this is the B-5 lock. The tile consumes it kind-specifically in `PageEmbedBlock`/`ViewEmbedBlock`.

**Tier C — Container view-lock (G-5):** locks a Collection/Set's views everywhere (not just embeds).
- Seams: a lock in `Toolbar/ViewPane.tsx`'s `MenuBottomRow`; when engaged, dims the SettingsPane + ViewPanes container-wide (config + view CRUD disabled); persists in the container's sidecar. **Standalone-buildable** — doesn't depend on the block system, so it can split to its own commit.

**Gate:** each tier's gating verified live (locked host can't drag; locked page can't edit but opens; locked view freezes config, drags live; locked container dims its panes) + main-side sidecar round-trip tests.

---

### Task 6.2 — Insert Menu (G-9)

**What it does (plain):** right-clicking the empty homepage background drops a markdown block today. Upgrade it to a **Page / View / Block** choice through the same picker the drag handle uses.

**Seams:**
- `src/renderer/src/Blocks/BlockSurface.tsx` — `onBackdrop` (the current direct-create) and the shipped `pagePickerItems`/`viewPickerItems` + `applyPagePick`/`applyViewPick` (the drill trees already built for the handle menu).
- `BlockHandleMenu.tsx` / `PickerMenu` — the picker shell to reuse.

**Approach:** the background right-click opens the picker at the click point with a root of **Page** · **View** (→ the existing source drill: Collections → Sets chevron → views, + Custom footer) · **Block** (→ the current `createMarkdown`). The wedge/append target resolution (`onBackdrop`'s `BackdropTarget`) is already built and unchanged — only the create step gains the menu in front of it. **Ordering:** the Page entry routes to Task 6.3's search pane, so either land 6.3 first, or wire Insert→Page to the **existing `pagePickerItems` drill** (`BlockSurface.tsx`, what the handle's Link Page uses today) as an interim that 6.3 later upgrades at both entry points. Don't ship Insert→Page as a dead entry.

**Gate:** each path creates the right tile at the right target (wedge vs append) + the picker flows verified live.

---

### Task 6.3 — Link Page Search Pane + Shared Recents

**What it does (plain):** embedding a page (via Insert → Page, or the handle's Link Page) opens a search — type to filter, results as icon + title over the `Collection › Set` path, recently-opened pages first until you type.

**Seams:**
- **Shared recents record** — `.nexus/state.json` session-state. A capped, ordered list of recently-opened page ids, appended on page open. Built here as the **shared** record (Navigation adopts it, per the ratified call) — NOT a Link-Page-local list. (`appConfig.recents` is the recently-opened *nexus directories*, unrelated.)
  - **Concurrency prerequisite:** `crud/reorder.ts`'s `setStateOrder` writes state.json via `mutateJson` with **no file lock** — tolerable for rare drag-reorders, but a recents-append fires on *every page open* (nav bursts), so mirroring it risks lost updates (append-vs-append, and an append racing a reorder). Route **all** state.json writers (the new recents-append *and* `setStateOrder`) through `serializeOnFile(statePath)` — the same path-keyed mutex `blocks.ts` uses for homepage.json. This is a prerequisite of the task, not an afterthought.
  - **Append point:** the renderer's `select()` path (`store.ts`) is the hook, but it's also called with `{ record: false }` for non-nav refetches (reveal, refetch-after-rename) — append **only on genuine nav**, and dedupe / move-to-front on a repeat open, or recents fills with same-page re-selects.
- **The search pane** — a `PickerMenu`-hosted scrolling search over all Collections' pages; result rows reuse the menu row + path breadcrumb tone; recents-descending seed until the query is non-empty.

**Approach:** build the recents record + its narrow IPC first (locked append-on-open + read), then the pane consumes it. The pane resolves a `page_id` and hands it to `applyPagePick` (Task 6.2's flow) — so Insert → Page and the handle's Link Page share one pane.

**Gate:** recents round-trip (open pages → surface newest-first; a `record:false` refetch doesn't pollute; concurrent appends don't drop) + typed search filters + a pick resolves the embed. Shared-record test so Navigation can rely on the same shape.

---

### Task 6.4 — Page-Embed Header

**What it does (plain):** the view-embed header is done; the page-embed still needs its hover ⋮ menu. **Banners are deferred** (Nathan: "pages don't need banners for embeds for now") — so this narrows to the `title` toggle + the ⋮ menu itself (mirroring the view-embed title-row menu). Do this BEFORE the B-5 page-embed lock, whose toggle has no home until this menu exists.

**Seams:** `src/renderer/src/Blocks/PageEmbedBlock.tsx` + `src/renderer/src/Embeds/PageEmbed.tsx`. The `banner`/`title` fields exist on `PageBlockEntry` **in the schema only** — `PageEmbedBlock` doesn't forward them and `PageEmbed`'s header chrome is parked/unrendered. So this is three pieces, not one: **thread** `banner`/`title` from the entry through `PageEmbedBlock` → `PageEmbed`, **render** the banner/title conditionally, and **add the ⋮ toggle** (the G-4 top-right hover chrome, mirroring the view-embed title-row menu). There is **no `display_title` on page embeds** — a page embed's title is the real page's title (H-2/G-6: you can't rename a source from an embed), so the ⋮ toggles `banner` + `title` visibility only, no per-block title override.

**Gate:** the ⋮ toggles flip the page-embed's banner/title live + persist on the entry (absent = shown, per G-4).

---

### Verification Discipline

Per task: design disclosure (disclose-before or screenshot-after, never neither) → gates (`npm run typecheck` + `vitest` from `Pommora/`) → build-breaking-agent review, findings verified first-hand → fold → commit. Re-ground each task's cited seams before writing its code. Post-functional UIX review closes each visible surface.
