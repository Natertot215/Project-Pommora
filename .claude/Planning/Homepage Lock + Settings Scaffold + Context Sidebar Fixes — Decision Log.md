## Homepage Lock + Settings Scaffold + Context Sidebar Fixes — Decision Log

Grounded, pre-ratification. The focused plan Nathan scoped after deferring contexts-as-block-hosts ([[Context Block Hosts — Decision Log]], parked). Covers three things: (1) homepage board locking; (2) a Homepage + Context SettingsPane icon+title scaffold; (3) two context-sidebar-creation bug fixes.

### Frame

- **Purpose:** Finish the block-surface locking on the existing homepage host, give the homepage + contexts a real SettingsPane (icon+title) instead of the placeholder, and fix the glitchy/misscoped context creation in the sidebar.
- **Core Value:** The homepage board can be frozen; homepage + contexts have a proper identity settings pane; creating a context in the sidebar scopes to its tier and lets you name/icon it without glitching.
- **Success Criteria:** Toggling the homepage's SettingsPane footer lock freezes the whole board (no drag/resize/create, borderless pinned) and persists (`blocks_locked`); homepage + context SettingsPanes render icon+title; per-tier context creation lands in the right tier and the new row names + icons cleanly.

### Sources

- `src/renderer/src/Blocks/useBlockDoc.ts` — exposes `locked` (from `BlockDoc.locked`/`blocks_locked`, :16/:52) but has **no `setLocked`**; `save` path is `window.nexus.blocks.save(host, patch)` (:62/:112). Reload effect keys on `[host.kind]` (:57).
- `src/main/blocks.ts` — `writeBlockDoc` handles `locked` (:78-81); the round-trip works.
- `src/renderer/src/Embeds/ViewEmbedScope.tsx` + `src/renderer/src/Components/Detail/SettingsPane.tsx:196-199` — the view-embed footer lock (`scope.locked`/`setLocked` + `footerLock`/`footerLockActive`) — the UI template for both new footer locks.
- `src/renderer/src/Components/Detail/SettingsPane.tsx:140-158` — `InlineEditHeader` (icon + title + rename), derives `node.title`/`node.icon` for collection/set. The scaffold header reuses this.
- `src/renderer/src/Components/Detail/SettingsDropdown.tsx:27` — routes `scope==='view'`→SettingsPane, else an empty placeholder. The route to extend for homepage + context.
- `src/renderer/src/Detail/HomepageView.tsx:15` — homepage identity = `{ kind:'homepage', name: tree.nexus.name ?? 'Home', banner }` (no icon today).
- `src/renderer/src/Detail/DetailTitleHeader.tsx` + `DetailScaffold.tsx` — how a context's icon+title already renders in the detail (via `findContext`).
- `src/renderer/src/Sidebar/Sidebar.tsx:410-415` — Contexts create is ONE global menu (New Area/Topic/Project → `op:'createContext', tier:1|2|3`), wired `onCreate = mode==='contexts' ? …`; `TierDisclosure` (:364) has no per-tier create. (Bug 3a.)
- `src/main/mutate.ts:172` — `createContext` op; `:211-212` — context rename renames the folder, id stable.
- Sidebar inline name/icon glitch (Bug 3b) — root-cause pending the sidebar explorer.

### Decisions

#### A — Homepage Board Lock (Tier A / G-3)
- **A-1:** [confirmed] The lock persists as `blocks_locked` (round-trips already). Add a `setLocked` to `useBlockDoc` = one `blocks.save(host,{locked})`.
- **A-2:** [assumed] Cross-tree state sync: the homepage lock rides the **store** (cached from the host doc, persisted via `blocks.save` on toggle), read by BOTH the toolbar-dropdown SettingsPane (toggle) and the detail-pane BlockSurface (freeze) — a React scope can't bridge the two subtrees. ← recommend; confirm.
- **A-3:** [confirmed] Board freeze = every tile static (drag+resize gated — reuse the per-tile `isTileStatic` path, host-locked ⇒ all true), no background-create (`onBackdrop` no-ops), and the borderless chassis pinned hidden (G-14). The handle still opens its menu (so a locked board's tiles can still be inspected/unlocked-at-tile — TBD if per-tile lock even shows under a host lock).

#### B — SettingsPane Icon+Title Scaffold
- **B-1:** [confirmed] `SettingsDropdown` routes homepage + context selections to a **stripped scaffold** — the SettingsPane header (icon+title) + (homepage only) the footer lock, with NO view-config leaves (Layout/Group/Filter/Sort/Configuration are view concepts).
- **B-2:** [confirmed] Homepage identity: title = `tree.nexus.name`, **display-only** (no rename from the pane). Context identity: `node.icon` + `node.title` via `findContext`. Homepage gains a fixed home glyph (not user-editable).
- **B-3:** [confirmed] Contexts get **icon+title only — no footer lock** (not block hosts yet, nothing to freeze). Homepage gets icon+title + footer lock (= A). Collection/Set footer lock (Tier C) is OUT of this plan.
- **B-4:** [confirmed] "Hide/show icon" is NOT a new right-click menu — it's the **existing banner heading toggle**, applied to homepage + contexts (the header icon+title show/hide rides the banner's heading-visibility mechanism, G-4 chrome). No separate persistence to invent; wire homepage + context into the banner-heading toggle. ← ground the banner heading toggle when planning.

#### C — Context Sidebar Creation Fixes (root-caused)
- **C-1:** [confirmed] Bug 3a — there is exactly ONE create entry point in Contexts mode: the global 3-item menu (`newContext`, `Sidebar.tsx:411-417`, on `.mode-body`'s `onContextMenu`). `TierDisclosure` (`Sidebar.tsx:364-371`) has NO create affordance. Fix: `TierDisclosure` hosts a scoped per-tier "+" (it already knows its `tierKey`) → `mutate({op:'createContext', tier, name})` directly. ← confirm placement (per-tier header "+" hover-revealed vs right-click).
- **C-2:** [confirmed] Bug 3b-icons — `ContextRow` (`Sidebar.tsx:337-354`) omits `icon` from its node type and hardcodes `defaultEntityIcon(node.kind)` (:344), never reading `node.icon` (which `readNexus.ts:342` populates); `ContainerRow` honors it via `folderAwareIcons`. And `Leaf` (:85-121) has no icon-click/picker (every `IconPicker` lives in detail panes). Fix: `ContextRow` reads `node.icon`; decide whether a sidebar icon affordance is in scope or icons stay detail-set.
- **C-3:** [confirmed] Bug 3b-names — the create→rename handoff is racy: `newContext` rides `popCreateMenu`→`create-menu` IPC, and main fires `reload-state` THEN `begin-rename` back-to-back with **no `onCreated` callback** (unlike `store.newPage:456`, which awaits `load()` then selects). The rename input only mounts after the async refetch, and `EditableInput`'s uncontrolled `defaultValue` + 60ms re-focus/select-all wipes keystrokes on any remount. Remount churn: `createFolderEntity`'s `mkdir` is NOT echo-suppressed (`writeEcho`) → a racing `nexus:changed` tree swap while typing; `readTier` skips a sidecar-less tier dir (:337) → row unmount/remount. **Fix at source:** port `createContext` onto the `store.mutate`+`onCreated` pattern (create → `load()` resolves → select + begin-rename on the existing row), and echo-suppress the folder `mkdir`. (Note: Collections share the same racy path — the fix generalizes; contexts feel worse from the nested `Leaf`/`Reveal` + icon gap.)

### Core (must-have)
- `useBlockDoc.setLocked` + store-synced homepage lock; BlockSurface board freeze (A-3).
- Homepage SettingsPane scaffold (icon+title + footer lock); Context SettingsPane scaffold (icon+title); SettingsDropdown routing.
- Per-tier context creation (C-1); inline name/icon glitch fixed at source (C-2).

#### Prospects (allowed later, not now)
- Context footer lock (lands with contexts-as-block-hosts, [[Context Block Hosts — Decision Log]]).
- Collection/Set footer lock (Tier C) — separate plan.

#### Out of Scope (won't do)
- Contexts becoming block hosts (deferred). Contexts get the settings identity pane only, no surface.

#### Considered & Rejected
- Homepage lock via a React scope context (like the view-embed) — the dropdown SettingsPane and the detail BlockSurface are different subtrees, so a scope can't reach across. Store-synced instead (A-2).

#### Lessons
- (pending)
