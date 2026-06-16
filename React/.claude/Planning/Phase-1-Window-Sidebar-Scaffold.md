## Pommora React — Phase 1: Window + Glass Sidebar Scaffold

> **Read-only walking skeleton.** A real Electron window that reads the test nexus from disk and renders its true structure in a liquid-glass sidebar — with **zero function** (no selection, CRUD, drag, rename, editor, or writes). Backed by the Swift nexus-management scope (7-agent workflow) + the real `~/test` fixture.

**Goal:** Prove the full read stack end-to-end — `fs walk (main) → IPC → one immutable tree → store → glass sidebar` — so every later feature has a clean foundation to plug function *into*.

**Architecture:** Electron two-process. The **main** process owns all filesystem access and runs ONE recursive read of the nexus, returning one pre-ordered, serializable `NexusTree` over a single typed IPC call. The **renderer** is pure presentation: a tiny session store (idle/loading/ready/error) + a recursive `<SidebarNode>` on a liquid-glass `<Surface>`. **No SQLite** — the single fs walk is the only read source (this is exactly how the Swift sidebar actually works; the GRDB index only powers query/filter, which is deferred).

**Tech stack:** electron-vite · React + TS (strict) · Zustand · `eemeli/yaml` · `liquid-glass-react` · Vitest. `contextIsolation` on, `nodeIntegration` off, `sandbox` on.

---

### The gate

Window opens → reads `~/test` → the sidebar shows its true structure (Vaults A/B/C → Collections → Pages) on a glass surface, with expand/collapse working and **nothing else wired**. If that stands, the architecture is proven and every later phase assigns function to this skeleton.

---

### Test nexus — `~/test`

`~/test` is the fixture (overridable via `TEST_NEXUS_PATH`). Confirmed state: **raw, un-adopted** — no `.nexus/`, no sidecars. Contents: `Vault A` (→ `Collection A` with `Page A/B/C.md`, `Collection B`), `Vault B` (Collections A/B), `Vault C`, plus `Tasks` / `Events` / `Agenda` and `.trash`.

**Consequence — the walker must classify by structure, not by sidecar.** Because there are no `_pagetype.json` etc., the read engine can't gate on sidecars for this fixture; it classifies by **folder structure** (the adoption read path): root folder → Vault (PageType), sub-folder → Collection, deeper folder → Set, `.md` → Page. IDs are synthesized as `adopted-<shortHash(relPath)>` (stable across reads — hash the *relative* path). The engine supports **both** paths: sidecar-driven when `.nexus/`/sidecars exist, structure-driven when absent. `~/test` exercises the harder structure-driven path — the more realistic case.

What `~/test` populates in the sidebar: the **Vaults** section (A/B/C → Collections → Pages). No Contexts (no `.nexus/areas|topics|projects`). `Tasks`/`Events`/`Agenda` are **discovered but not surfaced** (folded into the deferred Calendar pin) — name-matched out so they don't render as vaults.

---

### The keystone — `NexusTree` shape (`@shared/types.ts`)

The renderer consumes ONE pre-ordered tree and never sorts. Single source of truth, importable by main + preload + renderer:

```ts
type NodeKind = 'saved'|'area'|'topic'|'project'|'pageType'|'collection'|'set'|'page';
type AreaColor = 'gray'|'brown'|'orange'|'yellow'|'green'|'blue'|'purple'|'pink'|'red'|'accent'; // 10-case
// Keep distinct from Settings.accentColor (separate 8-case enum) — do not conflate.

interface BaseNode { id: string; kind: NodeKind; title: string; icon?: string; } // title = basename, never on disk
interface SavedNode      extends BaseNode { kind:'saved'; key:'homepage'|'calendar'|'recents'; }
interface AreaNode       extends BaseNode { kind:'area'; color?: AreaColor; } // only tier with color
interface TopicNode      extends BaseNode { kind:'topic'; }
interface ProjectNode    extends BaseNode { kind:'project'; }
interface PageNode       extends BaseNode { kind:'page'; } // leaf; id = frontmatter id OR 'adopted-<hash>'
interface SetNode        extends BaseNode { kind:'set'; selectable:false; pages: PageNode[]; }
interface CollectionNode extends BaseNode { kind:'collection'; sets: SetNode[]; pages: PageNode[]; } // sets before pages
interface PageTypeNode   extends BaseNode { kind:'pageType'; collections: CollectionNode[]; pages: PageNode[]; } // collections before pages

interface UserSection { id: string; label: string; vaults: PageTypeNode[]; }
interface NexusTree {
  nexus: { id: string; rootPath: string };
  saved: SavedNode[];                                              // fixed 3
  contexts: { projects: ProjectNode[]; topics: TopicNode[]; areas: AreaNode[] }; // render P→T→A
  vaults: PageTypeNode[];                                          // ungrouped PageTypes
  userSections: UserSection[];
  labels: { vaults: string; areas: string; topics: string; collection: string; set: string };
}
```

Children are **typed arrays** (collections/sets/pages), not a generic `children[]`, so Collections-before-Pages / Sets-before-Pages ordering is structural, not a sort flag.

---

### The read engine — `readNexus(rootPath): NexusTree`

One pass in main, fully read-only (no file ever opened for writing):

1. **Identity gate.** If `<root>/.nexus/nexus.json` exists → read `{id}` (sidecar path). If absent (the `~/test` case) → synthesize identity (`adopted-<hash(rootPath)>`) and take the **structure-classification** path. Unreadable root → `{ok:false}`.
2. **Config reads** (sidecar path only; defaults when absent): `settings.json` (`excluded_folders` + `labels`), `state.json` (sibling order arrays), `saved-config.json`, `sidebar-sections.json`. For `~/test` these are all defaults.
3. **Contexts** (sidecar path): folders under `.nexus/{areas,topics,projects}` carrying `_area/_topic/_project.json`. Empty for `~/test`.
4. **Vaults.** Sidecar path: root folder with `_pagetype.json` → recurse for `_pagecollection.json` (Collection) → `_pageset.json` (Set). **Structure path (`~/test`):** every non-excluded root folder (minus name-matched agenda singletons) → PageType; sub-folders → Collections; deeper → Sets. Title = `path.basename`.
5. **Pages (4 locations).** Collect `.md` (skip `_`-prefixed) at vault-root, collection-root, in-collection, in-set. **Roll-up rule (Obsidian parity):** loose `.md` in a non-container sub-folder rolls up into the nearest recognized container; Collection/Set sub-folders load as their own nodes. Lenient frontmatter: split on `---` fences, no fence → whole file is body + empty frontmatter, unterminated → skip-gracefully. `id` = frontmatter `id` else `adopted-<shortHash(relPath)>`; `title` = basename.
6. **Exclusion.** Every `readdir` runs `shouldSkipDir(name, relPath, excluded_folders)`: skip `.`/`_`-prefixed, `node_modules`, and user excludes (NFC + lowercased, segment-prefix on relative path). One pure function.
7. **Agenda singletons.** Discover `Tasks`/`Events`/`Agenda` (by `_taskconfig/_eventconfig.json` sidecar, else by conventional name) → cache on the tree, **not surfaced** in the Phase-1 sidebar.
8. **Ordering.** `resolveOrder` at every sibling level: persisted order array first (drop tombstones), unreferenced appended by `localeCompare(title)`; no/empty order → sort by `id` ascending (ULIDs are time-sortable). For `~/test` (no order arrays) → id-ascending then alpha tail.

---

### Glass — the sidebar `<Surface>`

The sidebar pane is the glass surface. Pair the native window material with the component, isolated in one swappable seam:
- BrowserWindow: `vibrancy: 'sidebar'`, `titleBarStyle: 'hiddenInset'`, transparent where needed.
- `<Surface variant="sidebar">` wraps the sidebar, rendering **`liquid-glass-react`** with **locked settings: saturation 100, cornerRadius 26, blur 0.3** (refraction/displacement/chromatic/elasticity tuned to Figma). Chromium-only is a non-issue — Electron is all-Chromium.
- **Glass on the pane, not per-row** — one backdrop surface behind the rows (perf); rows are transparent content on top. Selection chrome (later) will be a cheap flat fill, not per-row glass.
- `<Surface>` is one styled wrapper so the material is a single swap-point, not scattered CSS.

---

### Tasks

**Task 1 — Scaffold.** electron-vite (`npm create @quick-start/electron`, react-ts); `main/`/`preload/`/`renderer/`; strict TS + `@shared/*` alias; BrowserWindow flags above; `TEST_NEXUS_PATH` constant (default `~/test`).
- *Produces:* launchable empty window, React mounting, separate build outputs.
- *Verify:* `npm run dev` opens a window; renderer console: `window.require` is `undefined` (contextIsolation correct).

**Task 2 — Shared types.** `@shared/types.ts`: the `NexusTree` union above + parsed-JSON types (Identity/Settings/State/SavedConfig/SidebarSections) + IPC envelope `{ok:true; tree} | {ok:false; error}`. No fs, no React.
- *Produces:* compile-checked cross-process contract.
- *Verify:* `tsc --noEmit` passes; type imports from both main + renderer compile.

**Task 3 — Paths module.** `main/paths.ts`: pure functions over `rootPath` for `.nexus/<config>.json`, context folders, flat PageType folders, nested collection/set, per-kind sidecar filenames. `node:path` only.
- *Produces:* one place that knows the layout.
- *Verify:* Vitest asserts computed paths for a known root.

**Task 4 — Exclusion + order.** `main/exclusion.ts` (`shouldSkipDir`) and `main/order.ts` (`resolveOrder`), pure + tested.
- *Produces:* the exact skip + ordering semantics, independently testable.
- *Verify:* Vitest: `shouldSkipDir` true for `.git`/`_x`/`node_modules`/configured exclude, false for normal; `resolveOrder` reproduces id-asc fallback + known-then-alpha-tail.

**Task 5 — Read engine.** `main/readNexus.ts`: the recursive walker per the read plan, supporting **both** sidecar-driven and structure-classification paths, lenient frontmatter (`eemeli/yaml`), `adopted-<hash(relPath)>` ids, roll-up rule, ordering, agenda discovery (hidden).
- *Produces:* `readNexus(rootPath) → NexusTree`, runnable headless.
- *Verify:* Vitest against `~/test`: Vaults A/B/C present with correct Collections/Pages; `Tasks`/`Events`/`Agenda`/`.trash` absent from `vaults`; `Page A/B/C` under Vault A › Collection A; ids stable across two reads. (Add a tiny checked-in `fixtures/sidecar-nexus/` to also cover the sidecar path + the no-frontmatter / unterminated-fence / roll-up edge cases.)

**Task 6 — IPC bridge.** `main`: `ipcMain.handle('nexus:open', () => safeReadNexus(TEST_NEXUS_PATH))` → `{ok,...}` envelope (try/catch → `{ok:false,error}`). `preload`: `window.nexus.open()` via contextBridge — the only renderer-visible API.
- *Produces:* typed one-round-trip read bridge.
- *Verify:* renderer DevTools `await window.nexus.open()` returns the tree; pointing at a folder with no readable structure returns `{ok:false,error}`.

**Task 7 — Session store.** Renderer Zustand: `{ status:'idle'|'loading'|'ready'|'error', tree:NexusTree|null, error? }` + `load()` calling `window.nexus.open()`; called once on mount.
- *Produces:* the three launch states in one store.
- *Verify:* mount transitions idle→loading→ready; error path renders the error branch.

**Task 8 — Window shell + glass `<Surface>`.** Two-pane layout: glass sidebar pane (`<Surface variant="sidebar">` + `liquid-glass-react` at sat100/r26/blur0.3) + empty content pane. Honor loading/error/empty.
- *Produces:* the app shell — glass sidebar + empty content pane.
- *Verify:* translucent sidebar material against desktop; loading shows spinner; error shows designed state; resize keeps the seam.

**Task 9 — Recursive sidebar render.** `<SidebarNode>` switches on `node.kind`; renders four fixed sections in order (Saved → Contexts[P→T→A] → Vaults → userSections); local `useState` expand/collapse; central `kindDefaults: Record<NodeKind, IconName>` (node.icon overrides); Area rows show a color swatch; Pages are leaves; Sets `selectable:false`. **No selection, no CRUD, no drag.**
- *Produces:* the full read-only sidebar rendering `~/test`'s true structure on glass.
- *Verify:* four sections in order; Vaults show Collections-before-Pages; all real pages appear; icons render; expand/collapse works; **no** selection/CRUD affordances exist.

---

### Out of scope (the read/write boundary)

Deferred to function-tier phases: selection→detail, detail-pane content, CRUD, drag/reorder, rename, the editor, properties UI, live-refresh / file watcher, and **all writes** (atomic-write, frontmatter-merge, trash, adoption-that-writes-sidecars). The read path is read-only by construction — the entire sandbox/bookmark/migration/index machinery is simply *absent*, not guarded.

---

### What we improve over Swift (built into this design)

- **One eager walk → one IPC → one immutable tree.** Kills Swift's three parallel page dicts, lazy per-row `.task{loadAll}`, the defensively-synced SQLite index, and 18 per-manager error fields → one walk, one store, one status/error.
- **The entire macOS sandbox layer is gone.** No security-scoped bookmarks, ref-counting, `isStale` refresh, NSOpenPanel retry loops, or the XCTest launch-modal guard — "remember last nexus" is a path string; tests point the walker at a fixture.
- **One `shouldSkipDir`** unifies the exclusion policy Swift hard-codes in four places + `FolderFilter` separately.
- **Distinct on-disk vs in-memory types** remove Swift's `title=''`-then-patch decode ritual (one `deriveTitle(path)` helper).
- **Typed error envelope → a real designed empty/error state** from day one (Swift sets `pendingError` but never surfaces it).
- **Glass as one `<Surface>` seam** — swappable, the right foundation before any content/selection chrome.

---

### Decisions — locked & open

**Locked:** test nexus = `~/test` (env-overridable); no SQLite; agenda discovered-but-hidden; saved strip rendered inert (proves section order); split-view shell present with an empty right pane; glass = `liquid-glass-react` (sat100/r26/blur0.3); format *modernization* is a write-side concern — Phase 1 reads leniently and changes nothing on disk.

**Open (confirm before build):**
- **Glass acceptance bar** — native `vibrancy` + `liquid-glass-react` will be a *credible* match, not pixel-identical to SwiftUI's NSVisualEffectView/26 Liquid Glass. Acceptable for Phase 1 (prove the seam), with a design pass as a follow-on? (Recommended: yes.)
- **Right pane** — empty shell now (recommended) vs a "select an item" placeholder.
