## Desktop & Filesystem Integration — Plan (V2, adversarially reviewed)

**Goal:** Make the app open, persist, write, and read a real on-disk nexus, with native macOS UI (menus, dialogs, Finder) for every access point — so it behaves like a real Mac app, not a sandboxed web view.

**Status:** V1 drafted → 4-agent adversarial pass → **V2** (findings folded; correctness + security fixes baked in; two scope decisions flagged **D1/D2**).

**Grounding (verified):** Electron 42 + electron-vite; renderer sandboxed (main is *not* — full fs in main); **not** MAS-sandboxed → persist the path, no security-scoped bookmarks. SQLite index FKs: `page_types → collections → sets → pages` cascade, but `context_links` / `connections` / `property_definitions` have **no FKs** (`schema.ts:78-109`) → deletes must clean them explicitly. Index is regeneratable + off the read path.

### What the adversarial pass changed (V1 → V2)

- **`deleteEntity` must explicitly clean orphans** — no FK on link/connection/property tables, so `DELETE FROM <kind>` alone strips the row but leaves dangling links.
- **Renderer sends RELATIVE paths + ids, never absolute** — safe-by-construction; main resolves under root. (The tree already carries `PageNode.path` as nexus-relative.)
- **Path validation must use `realpath`** — the current read guard (`index.ts:68-73`) uses `resolve`/`relative` only, which a symlink inside the nexus pointing out defeats. Extract a shared validator; backport to the read path.
- **`renameCascade` must re-index touched connections** — it rewrites page bodies but not the `connections` table → silent body↔index divergence.
- **Reorder is file-only** — no index transact (order lives in `state.json` / sidecars).
- **Partial failure:** file-then-index ordering + on-error tree refetch; the regeneratable index (rebuild) is the backstop.
- **Watcher reframed, kept in v1** → the V1 draft's *pause-flag* design was the real risk; V2 uses a *debounced idempotent re-read* (watcher only reads → echo is a no-op re-read, no pause → nothing dropped). `chokidar` + `awaitWriteFinish` added; ⌘R Reload ships alongside as a manual fallback.
- **Cheap native wins folded in:** `nativeTheme` (follow OS dark/light), Open With default app (`shell.openPath`), About panel, drag-a-folder-onto-the-window to open.

### Decisions (resolved)

- **D1 — Delete target = a user setting.** `trashMode: 'nexus' | 'system'` in app config (`pommora.json`), default **`nexus`** (portable-safe). `nexus` → `deletePage` to the nexus `.trash` (tested, portable, index-aware); `system` → `shell.trashItem` (macOS Trash, Finder-recoverable). The mutate delete handler branches on it; the index row is cleaned either way. A device-level pref (system Trash is mac-only, so it's not portable nexus data). Settings UI deferred — config-editable now, like the accent.
- **D2 — Live watcher is IN v1**, built with the **robust idempotent-re-read design** (not the fragile pause-flag the V1 draft assumed). The watcher only ever *reads*: on a debounced settle it re-reads the tree and replaces it in the renderer. Echo from in-app writes is a harmless redundant re-read (a read-only watcher can't loop; an identical tree re-render is a no-op); with no pause window, no external change is dropped. `chokidar` + `awaitWriteFinish` coalesces atomic-rename events. A ⌘R Reload ships alongside as a manual fallback.

### Architecture decisions

1. **Main owns all OS surface.** Renderer (sandboxed) never touches `fs`/Electron natives; everything is a narrow IPC handler.
2. **Persist the path, not a bookmark.** `userData/pommora.json` = `{ lastNexusPath, recents[], windowBounds }`. A `resolveNexusAccess(path)` seam isolates the one spot bookmarks slot into *if* MAS ever ships.
3. **One mutate contract.** Single `mutate` IPC; request carries `{ op, relPath/ids, … }` (RELATIVE); main resolves + validates under root, then runs one orchestration.
4. **Index delete = explicit orphan cleanup**, not a bare row delete.
5. **Native-first UI** for menus / context menus / confirms / Finder.
6. **v1 = Reload, no watcher.**

### Path-safety (the security spine)

- `main/pathSafety.ts` → `resolveUnderRoot(root, relPath): Promise<{ ok: true; abs } | { ok: false; error }>`: `realpath` both sides + `relative` + reject `..` / absolute / escape. Used by **every** read and write. Backport into `page:open` + `readPage`.
- Renderer sends **nexus-relative POSIX** paths + ids; main never trusts a renderer-supplied absolute path.
- Defense-in-depth: `trashWithTimestamp` asserts its source is under root.

### Write orchestration contract

`resolveUnderRoot(relPath) → CRUD Result fn → if rename: renameCascade + reindex touched pages' connections; if context delete: unlinkTier(all tiers) → transact(index): upsertX / deleteEntity(+orphan cleanup) + replaceContextLinks/replaceConnections → return Result → renderer refetches tree`. On any error: refetch tree + surface "may be out of sync" (index rebuild is the backstop).

### deleteEntity — verified-correct shape

- **page:** `DELETE pages WHERE id` + `DELETE context_links WHERE source_id=id` + `DELETE connections WHERE source_id=id`.
- **container (page_type / collection / set):** gather member page ids first → clean their links/connections (+ `property_definitions WHERE owning_type_id` for a type) → delete the container row (FK cascades the child entity rows).
- **context (area / topic / project):** `DELETE contexts WHERE id` + `DELETE context_links WHERE target_id=id` (and `unlinkTier` strips it from page files).

### Phases — v1 = 0–4

**Phase 0 — appConfig + session + lifecycle. ✅ DONE (`05f9d78`).** `main/appConfig.ts` (userData json round-trip), `main/session.ts` (`{ root }` + open/close + `resolveRestorePath`). Removed `TEST_NEXUS_PATH`; restore `lastNexusPath` only if it's an existing dir, else empty state — restore is non-fatal, **never a launch modal** (headless/tests must not hang). IPC `nexus:state` (`empty | open | error`); store switches exhaustively. **Deviation:** the index `db` handle is deferred to Phase 3 — loading `better-sqlite3` in Electron-main needs `electron-rebuild` (native ABI), and no Phase-0 consumer reads the index. The renderer shell (App/Sidebar/DetailPane) already exists — Phase 1 replaces the bare "No nexus open" placeholder it now renders with the picker button + drag-to-open.

**Phase 1 — Native folder picker + recents. ✅ DONE (`bfde702` picker+recents, `6bd302e` drag-to-open).** `nexus:choose` → native picker (sheet) → `adoptNexus` (open session + persist `lastNexusPath` + deduped/capped recents via `addRecent` + `app.addRecentDocument`; persistence best-effort so a read-only userData can't block opening). `nexus:openPath` opens a dropped folder (preload resolves the `File` via `webUtils.getPathForFile`, sends only the path; main accepts only an existing dir). Interim empty-state "Open Folder" button. `choose`/`openDropped` share `openVia`, which resets the operational selection on session-switch — kept OUT of `load()` so Phase 4's watcher refresh preserves selection. **Deferred:** persist-before-read (a bad folder could persist as `lastNexusPath`) — acceptable: readNexus is tolerant + `isExistingDir` gates restore; revisit if strict nexus-signature validation lands.

**Phase 2 — Native app menu + theme. ✅ DONE (`94fa54b`).** `main/menu.ts` → `installAppMenu(win, adopt)`: appMenu / File (Open Nexus ⌘O → renderer `choose`, Open Recent → `adopt` + reload, New Page ⌘N **disabled until Phase 3**, Reveal in Finder, Reload ⌘R, Close) / Edit / View (Toggle Sidebar ⌘\ — hides the populated sidebar only, never the empty-state prompt) / Window / Help (About). Renderer-driven items send `menu:action` (reuse store actions); main-side act directly. Menu rebuilt on session/recents change (`refreshMenu`). **Deviations:** `nativeTheme.themeSource = 'dark'` (forced, not follow-OS — the renderer is dark-only; a light theme + `'system'` is a later task); **Open With** dropped (not needed yet). 2-agent review folded (`isDestroyed` send guard; toggle preserves Open-Folder).

**Phase 3 — Write path + context menus. ✅ DONE + adversarially reviewed.** `pathSafety.ts` (`resolveUnderRoot`, realpath, backported into `page:open`); container `path` exposed on every node DTO (`PathNode`) so a mutation can address folders too; `main/mutate.ts` — one `mutate` IPC over a discriminated request (relative paths only): create page/container/context (+ root-create), rename, delete, movePage. Cascade policy owned here: page rename → `renameCascade` with **revert-on-failure**; context delete → `unlinkTier` before the folder goes. Delete branches on `trashMode` (D1; in-nexus `.trash` vs injected `shell.trashItem`). `main/contextMenu.ts` — per-kind native menu (New / Delete→native confirm / Reveal in Finder), wired to every Sidebar row; New Page ⌘N end-to-end (selection-targeted, create-name disambiguation centralized in main). Live index = **full-refresh** (drop `index.db` + cold-rebuild after each mutation, reusing `buildIndex`) — `electron-rebuild`/`asarUnpack` wired; `db.ts` lazy-requires so an ABI mismatch degrades to a cold index, never crashes. Reactivity: tree refetch + selection reconcile (deleted → reset, renamed/moved → path refresh). **Deviations from the V2 draft:** (a) index is full-refresh, NOT incremental — `deleteEntity` was built then removed as unwired (git history keeps it; incremental + its primitive return with a query consumer); (b) **inline rename + top-level create shipped** — right-click → Rename → inline `<input>` (Enter/blur commit · Escape cancel); section-header "+" → New Vault (root create) + a native Area/Topic/Project picker → createContext; new entities land in inline-rename mode. Review-clean. Only the drag-to-move trigger (movePage handler exists) is left; (c) Open With dropped; (d) movePage handler exists but the drag-to-move trigger is deferred. **Packaged-index caveat:** electron-builder's `buildFromSource=false` rebuild is inconsistent here, so the packaged index may be cold (invisible — no index consumer until Views; the write path reads the filesystem). Adversarial review (4 agents) folded: never-throws IPC contract, Reveal path-guard (security), `.nexus`/`.trash` reserved guard, NUL-name reject, selection reconcile — all with tests.

**Phase 4 — Live watcher (robust). ✅ DONE + adversarially reviewed (`0f4d3c4`).** `chokidar` v5 in `main/watcher.ts`: watches the session root with an `ignored` predicate, `awaitWriteFinish` + `atomic` + a ~200 ms debounce; on settle → re-read tree → `webContents.send('nexus:changed', tree)`. **No pause flag** (idempotent re-read — a read-only watcher can't loop; an in-app-write echo is a harmless redundant re-read). Renderer swaps the tree via the shared `applyTree` (extracted from `load()`'s open case — DRY; no loading flash, selection reconciles). Lifecycle: start on adopt (the open funnel) + launch-restore (post-`createWindow`) + window reopen (activate); `startWatcher` replaces any prior session's; stop on quit. ⌘R Reload stays the manual fallback. **Review fixes folded:** (a) the draft's "ignore `.nexus`" was WRONG — Contexts (`.nexus/<tier>/`) + settings/state live there, so the predicate ignores only `index.db*` (the WAL-churning index) + `.trash` + dotfile cruft and DOES watch `.nexus/` (else external Context/accent/label/order edits never refresh); (b) added `.on('error')` — an unhandled EventEmitter `error` (EMFILE/ENOSPC) would otherwise crash the whole main process. **Residual (single-window v1):** a rare in-flight push during an in-window nexus switch self-heals via the switch's trailing `load()`; revisit if multi-window / in-app close lands.

### Deferred to v1.1
Drag pages OUT to Finder; Dock menu/badge; full-disk-access error UX; window + last-selection restoration; incremental/targeted re-read (vs full refetch) for large nexuses + autosave.

### UIX follow-ups (need a live-app pass before milestone closeout)

- **Phase 1:** interim "Open Folder" button → design-system Button when it ships; the draggable glass strip (`-webkit-app-region: drag`) may be a drop dead-zone — verify live and consider a drag-over overlay (which also adds the currently-missing drag affordance); non-folder drops reject silently (signal "drop a folder").

### Risk register — post-V2

- **Resolved:** R1 (non-MAS persist confirmed); R2 + R7 (watcher echo/races — dissolved by the idempotent-re-read design: a read-only watcher can't loop, no pause means nothing is dropped); R3 (deleteEntity orphan cleanup + rename reindex specified); R4 (realpath + relative-paths + trash assertion); R5 (restore-or-empty, no modal); R8 (read path already handles raw/un-adopted folders).
- **Residual:** R6 (menu closures must capture the live session, not a stale `win` — rebuild menu on nexus switch); partial-failure UX is "refetch + banner," real rollback is v1.1; full-tree re-read per change is fine at v1 sizes, targeted re-read is a v1.1 optimization.
