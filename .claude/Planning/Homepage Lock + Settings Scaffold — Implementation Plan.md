# Homepage Board Lock + Settings Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or subagent-driven-development) to implement this task-by-task. Steps use checkbox (`- [ ]`) syntax. Studio cadence: after each task ships green, dispatch a `build-breaking-agent` review before the next task; verify every finding first-hand at file:line before folding.

**Goal:** The homepage board can be frozen from a real settings pane, and the homepage + every context get an icon+title SettingsPane (replacing today's empty placeholder), with header-icon show/hide riding the banner heading menu.

**Architecture:** Reuse the shipped block-lock plumbing (`blocks_locked` round-trips already) — add the renderer setter + a store-synced lock so the toolbar-dropdown pane and the detail-pane surface share it across React subtrees. The settings scaffold reuses `SettingsPane`'s `InlineEditHeader` + the view-embed footer-lock UI, stripped of view-config leaves. Hide/show-icon extends the existing `nexus:titleMenu` with a per-entity icon-hidden flag (absent = shown, G-4).

**Tech Stack:** Electron 42 · React 19 · TS · Zustand · vanilla-extract · Vitest. Gates from `Pommora/`: `npm run typecheck` (two tsc passes) + `npx vitest run`.

## Global Constraints

- **Spec:** `.claude/Planning/Homepage Lock + Settings Scaffold + Context Sidebar Fixes — Decision Log.md` (sections A + B; the C/sidebar fixes already shipped — commits `fadba836`, `8a2505a6` — and are OUT of this plan).
- **Main owns fs; renderer touches it only via the typed IPC `{ok}` envelope.** No `fs`/Node in the renderer.
- **Colors are hex from `design-system/tokens`** — never `rgb()`, never hand-rolled.
- **Biome auto-formats on write** — don't hand-align; never run Biome. Typecheck is the only style-independent gate.
- **Contexts are sidecar-mode only** — `~/test` (raw folder) has none; exercise context UI against a sidecar nexus (Nathan's real Nexus via the CDP recipe, capture-restore).
- **Never commit `chip.css.ts`** (a live parallel edit) — stage explicit file paths every commit.
- **Do not push** — Nathan pushes `surfacepm` himself.
- **`blocks_locked` is the host lock (G-3);** absent/false = unlocked. The doc write is a locked read-merge-write that preserves foreign keys incl. `banner`.
- **`--mdpm-scale` / knob values live in code, not docs.** Reference tokens by name.

---

### Task 1: Host-lock plumbing — `setLocked` + store-synced homepage lock

**Files:**
- Modify: `src/renderer/src/Blocks/useBlockDoc.ts` (add `setLocked`; return it)
- Modify: `src/renderer/src/store.ts` (add `homepageLocked` slice + `setHomepageLocked` action + seed)
- Test: `src/renderer/src/Blocks/useBlockDoc.test.ts` (create if absent) OR a main-side round-trip in `src/main/blocks.test.ts`

**Interfaces:**
- Consumes: `window.nexus.blocks.save(host, { locked })` (exists — `writeBlockDoc` handles `locked`, `blocks.ts:78`); `readBlockDoc(...).locked` (exists).
- Produces: `useBlockDoc(host)` returns `setLocked: (locked: boolean) => void`; store exposes `homepageLocked: boolean` + `setHomepageLocked: (v: boolean) => Promise<void>`.

- [ ] **Step 1 — Main-side round-trip test (the lock persists + reads back).** In `src/main/blocks.test.ts`, add:
```ts
it('writeBlockDoc round-trips the host lock without touching foreign keys', async () => {
  const root = await tmpNexus() // existing helper in this test file
  await writeBlockDoc(root, HOST, { blocks: [{ id: 'a', type: 'markdown' }] } as any)
  await writeBlockDoc(root, HOST, { locked: true })
  expect((await readBlockDoc(root, HOST)).locked).toBe(true)
  await writeBlockDoc(root, HOST, { locked: false })
  const doc = await readBlockDoc(root, HOST)
  expect(doc.locked).toBe(false)
  expect(doc.blocks).toHaveLength(1) // foreign/sibling keys survive
})
```
(Use the file's existing `HOST` const + tmp-nexus helper; match their names.)

- [ ] **Step 2 — Run it, expect PASS** (the plumbing already exists; this pins the contract). Run: `npx vitest run src/main/blocks.test.ts`. Expected: PASS.

- [ ] **Step 3 — Add `setLocked` to `useBlockDoc`.** In `useBlockDoc.ts`, beside `saveBlocks` (:108), add:
```ts
const setLocked = useCallback((locked: boolean) => {
  setState((s) => ({ ...s, locked }))
  void window.nexus.blocks.save(hostRef.current, { locked })
}, [])
```
Return it: `return { ...state, setLayout, commitLayout, refreshEntries, saveBlocks, setLocked }` and add `setLocked: (locked: boolean) => void` to the hook's return type/interface (top of file).

- [ ] **Step 4 — Add the store slice.** In `store.ts`, add to the state interface: `homepageLocked: boolean` and `setHomepageLocked: (v: boolean) => Promise<void>`. In the store body add:
```ts
homepageLocked: false,
setHomepageLocked: async (v) => {
  set({ homepageLocked: v })
  await window.nexus.blocks.save({ kind: 'homepage' }, { locked: v })
},
```
Seed it on load: in the nexus-adopt / initial `load()` path (where `tree` is set), fetch once and set:
```ts
const doc = await window.nexus.blocks.get({ kind: 'homepage' })
if (doc.ok) set({ homepageLocked: doc.doc.locked })
```
(Place beside the existing post-adopt reads; keep it a fired side-effect, not on the render path.)

- [ ] **Step 5 — Typecheck.** Run: `npm run typecheck`. Expected: clean.

- [ ] **Step 6 — Commit.**
```bash
git add src/renderer/src/Blocks/useBlockDoc.ts src/renderer/src/store.ts src/main/blocks.test.ts
git commit -m "feat(blocks): host-lock setter + store-synced homepage lock"
```

---

### Task 2: Board freeze — a locked homepage can't drag/resize/create, borderless pinned

**Files:**
- Modify: `src/renderer/src/Blocks/BlockSurface.tsx` (consume the host lock; gate gestures + create + borderless)
- Modify: `src/renderer/src/SurfacePM/surfacepm.css` (pin borderless chassis hidden under a host lock)
- Modify: `src/renderer/src/Detail/HomepageView.tsx` (pass the store lock in)

**Interfaces:**
- Consumes: `useSession((s) => s.homepageLocked)` (Task 1); `isTileStatic` prop on `SurfaceView` (exists — per-tile freeze); `onBackdrop` (exists — the create path); `tileClassName` (exists).
- Produces: a locked host that freezes every gesture; `.blk-surface.is-host-locked` class for the CSS pin.

- [ ] **Step 1 — Thread the lock into BlockSurface.** `BlockSurface` already reads the doc via `useBlockDoc`. Add `hostLocked` from the store (single source, so the dropdown pane + surface agree): near the top of the component,
```ts
const hostLocked = useSession((s) => s.homepageLocked)
```
(Homepage is the only host today; when real hosts land, this keys by host — out of scope here.)

- [ ] **Step 2 — Freeze every tile.** Change the `isTileStatic` passed to `SurfaceView` (currently `(id) => entries.get(id)?.locked ?? false`) to also freeze when the host is locked:
```ts
isTileStatic={(id) => hostLocked || (entries.get(id)?.locked ?? false)}
```

- [ ] **Step 3 — Block background-create.** Guard `onBackdrop` (the create handler, `BlockSurface.tsx` ~289):
```ts
const onBackdrop = useCallback((target: BackdropTarget) => {
  if (hostLocked) return
  // …existing body…
}, [commitLayout, refreshEntries, host, hostLocked])
```

- [ ] **Step 4 — Pin borderless + tag the surface.** Add `hostLocked ? 'is-host-locked' : ''` to the `.blk-surface` className (`BlockSurface.tsx` :306). Then in `surfacepm.css`, pin the borderless chassis hidden (G-14: a locked host never reveals a tile's border/handle):
```css
/* A locked host freezes the board: borderless tiles never reveal their chassis, and the handle
   stays hidden (the board is inert until unlocked from its SettingsPane). */
.blk-surface.is-host-locked .spm-tile.is-borderless { border-color: transparent; }
.blk-surface.is-host-locked .spm-handle { opacity: 0 !important; }
```

- [ ] **Step 5 — Live-verify (real Nexus, CDP capture-restore).** Build + launch instrumented (the established recipe), toggle `blocks_locked:true` in `homepage.json` (capture the file first, restore after), reload, confirm: tiles don't drag/resize, right-click background creates nothing, borderless tiles stay borderless on hover. Restore `homepage.json`.

- [ ] **Step 6 — Typecheck + commit.**
```bash
npm run typecheck
git add src/renderer/src/Blocks/BlockSurface.tsx src/renderer/src/SurfacePM/surfacepm.css src/renderer/src/Detail/HomepageView.tsx
git commit -m "feat(surfacepm): host-lock freezes the whole board + pins borderless hidden"
```

---

### Task 3: Homepage SettingsPane scaffold — icon+title + footer lock

**Files:**
- Create: `src/renderer/src/Components/Detail/SettingsScaffold.tsx` (the stripped pane: identity header + optional footer lock)
- Modify: `src/renderer/src/Detail/ViewSettingsScope.ts` (add a `homepage` scope)
- Modify: `src/renderer/src/Components/Detail/SettingsDropdown.tsx` (route homepage → scaffold)

**Interfaces:**
- Consumes: `InlineEditHeader` (from SettingsPane's imports — icon+title+rename); `footerLock`/`footerLockActive` CSS (`settingsPane.css`); `useSession` for `homepageLocked` + `setHomepageLocked` (Task 1); `tree.nexus.name`.
- Produces: `<SettingsScaffold kind="homepage" />` renders icon (home glyph) + display-only title + a footer lock; `viewSettingsScope(...)` returns `'homepage'`.

- [ ] **Step 1 — Add the `homepage` scope.** In `ViewSettingsScope.ts`, extend the type to `'view' | 'page' | 'context' | 'homepage' | 'none'` and add the case:
```ts
case 'homepage':
  return 'homepage'
```

- [ ] **Step 2 — Build the scaffold.** Create `SettingsScaffold.tsx`. It renders the identity header (reuse `InlineEditHeader`; homepage title display-only → `onCommit` is a no-op, icon = a fixed home glyph) and, for the homepage, the footer lock (mirror SettingsPane's `scopedRoot` footer: `footerLock`/`footerLockActive`, `aria-label` Lock/Unlock board, `onClick` toggles `setHomepageLocked`). Concretely:
```tsx
import { InlineEditHeader } from './SettingsPane' // or its own module if not exported — export it
import { footerLock, footerLockActive } from './settingsPane.css'
import { useSession } from '@renderer/store'
import { Icon } from '@renderer/design-system/symbols'

export function SettingsScaffold(): React.JSX.Element | null {
  const tree = useSession((s) => s.tree)
  const locked = useSession((s) => s.homepageLocked)
  const setLocked = useSession((s) => s.setHomepageLocked)
  if (!tree) return null
  return (
    <>
      <InlineEditHeader value={tree.nexus.name} icon="house" onCommit={() => {}} />
      <div className="settings-footer-row">
        <button
          type="button"
          aria-label={locked ? 'Unlock board' : 'Lock board'}
          className={locked ? `${footerLock} ${footerLockActive}` : footerLock}
          onClick={() => void setLocked(!locked)}
        >
          <Icon name="lock" size={12} /> {locked ? 'Unlock' : 'Lock'}
        </button>
      </div>
    </>
  )
}
```
(If `InlineEditHeader` isn't exported from `SettingsPane.tsx`, export it there — it's the shared identity header. Match the footer-row wrapper class SettingsPane's `scopedRoot` uses so the footing metrics match.)

- [ ] **Step 3 — Route it.** In `SettingsDropdown.tsx`, change the pane switch so `homepage` shows the scaffold:
```tsx
{scope === 'view' ? <SettingsPane /> : scope === 'homepage' ? <SettingsScaffold /> : <div style={{ minHeight: 24 }} />}
```

- [ ] **Step 4 — Live-verify.** On the homepage, open the toolbar Settings dropdown → shows the home icon + nexus name + a footer Lock. Click Lock → the board freezes (Task 2) and the button reads Unlock; reopen the dropdown → still locked (store + disk synced). Unlock restores.

- [ ] **Step 5 — Typecheck + commit.**
```bash
npm run typecheck
git add src/renderer/src/Components/Detail/SettingsScaffold.tsx src/renderer/src/Detail/ViewSettingsScope.ts src/renderer/src/Components/Detail/SettingsDropdown.tsx src/renderer/src/Components/Detail/SettingsPane.tsx
git commit -m "feat(settings): homepage SettingsPane scaffold (icon+title + board-lock footer)"
```

---

### Task 4: Context SettingsPane scaffold — icon+title (no lock)

**Files:**
- Modify: `src/renderer/src/Components/Detail/SettingsScaffold.tsx` (handle the context case)
- Modify: `src/renderer/src/Components/Detail/SettingsDropdown.tsx` (route context → scaffold)

**Interfaces:**
- Consumes: `findContext(tree, id)` (`Detail/Scope.ts`) → the context node (`id, title, icon, kind`); the current `selection` (`{kind:'context', id}`).
- Produces: `<SettingsScaffold />` renders a context's icon + title (no footer lock — contexts aren't block hosts yet).

- [ ] **Step 1 — Generalize the scaffold.** In `SettingsScaffold.tsx`, branch on the selection kind: for `context`, resolve the node via `findContext(tree, selection.id)` and render `InlineEditHeader` with `value={node.title}`, `icon={iconNameOr(node.icon, defaultEntityIcon(node.kind, defaultIcons))}`, and `onCommit={(next) => next && next !== node.title && submitRename(node.path, node.kind, next)}` (contexts DO rename). Render NO footer lock for contexts (guard the footer on the homepage kind).

- [ ] **Step 2 — Route it.** In `SettingsDropdown.tsx`, extend the switch: `scope === 'homepage' || scope === 'context' ? <SettingsScaffold /> : …`.

- [ ] **Step 3 — Live-verify (sidecar nexus).** Select a context (Area/Topic/Project) → the Settings dropdown shows its icon + title, no lock. Rename from the header updates the context (folder rename, id stable). No footer lock present.

- [ ] **Step 4 — Typecheck + commit.**
```bash
npm run typecheck
git add src/renderer/src/Components/Detail/SettingsScaffold.tsx src/renderer/src/Components/Detail/SettingsDropdown.tsx
git commit -m "feat(settings): context SettingsPane scaffold (icon+title, no lock)"
```

---

### Task 5: Hide/show header icon — the banner heading toggle (homepage + contexts)

**Files:**
- Modify: `src/main/index.ts` (`nexus:titleMenu` handler ~1392 — add a Hide/Show Icon item)
- Modify: `src/preload/index.ts` (`titleMenu` return type ~322)
- Modify: `src/renderer/src/Detail/Banner/Banner.tsx` (handle the new action → toggle the flag; honor it in render)
- Modify: `src/shared/types.ts` (add the icon-hidden flag to the owner/config shape)
- Modify: `src/main/readNexus.ts` (read the flag onto homepage + context nodes) and the sidecar/homepage.json writer

**Interfaces:**
- Consumes: `window.nexus.titleMenu()` (returns the menu action); the banner's `owner` (`{ kind, path, name, icon, banner }`).
- Produces: `titleMenu()` returns `'rename' | 'editIcon' | 'toggleIcon' | null`; entities carry `headingIconHidden?: boolean` (absent = shown, G-4); the banner hides its heading icon when set.

- [ ] **Step 1 — Extend the native menu.** In `src/main/index.ts`, the `nexus:titleMenu` handler currently offers Rename + Edit Icon. Add a third item — `Hide Icon` / `Show Icon` (label chosen by a passed-in `hidden` arg) — resolving `'toggleIcon'`. Update the preload signature (`titleMenu: (hidden: boolean) => Promise<'rename'|'editIcon'|'toggleIcon'|null>`). (Mirror the view-embed title menu, `view-embed-title-menu` at index.ts:1295, which already does chrome toggles.)

- [ ] **Step 2 — The persisted flag.** Add `headingIconHidden?: boolean` to the entity config shape in `src/shared/types.ts`; read it in `readNexus.ts` onto the homepage node (`homepage.json`) and each context node (`readTier`, from the sidecar). Write it: on `'toggleIcon'`, the renderer calls a config write — for a context, `container.configure`-style sidecar write of `heading_icon_hidden`; for the homepage, `blocks.save`/a homepage.json field via the existing homepage-config writer (the same locked read-merge-write that holds `banner`).

- [ ] **Step 3 — Wire + render in Banner.** In `Banner.tsx`, pass the current `hidden` into `titleMenu(hidden)`; on `'toggleIcon'`, flip the flag via the write from Step 2. In render, when `headingIconHidden` is set, omit the heading icon (the homepage, which has no icon today, gains a fixed home glyph that this toggle shows/hides). Contexts hide their existing icon.

- [ ] **Step 4 — Live-verify.** Right-click the banner heading on the homepage → Show/Hide Icon toggles the home glyph; on a context → toggles its icon; persists across reload; the SettingsScaffold header (Tasks 3–4) reflects the same flag.

- [ ] **Step 5 — Typecheck + tests + commit.**
```bash
npm run typecheck && npx vitest run
git add src/main/index.ts src/preload/index.ts src/renderer/src/Detail/Banner/Banner.tsx src/shared/types.ts src/main/readNexus.ts
git commit -m "feat(banner): hide/show the heading icon from the title menu (homepage + contexts)"
```

---

### Closeout

- [ ] Run the full gate from `Pommora/`: `npm run typecheck && npx vitest run` — all green.
- [ ] Post-functional UIX review of the actual working homepage lock + both scaffolds (screenshot on the real Nexus, capture-restore) before calling it done.
- [ ] Update `Handoff.md` (via `/handoff`) and route the locked decisions to `History.md`; the decision log's B-4 (hide/show = banner toggle) becomes durable in `Features/Configuration.md` or the banner spec.

### Notes / seam facts (verified)

- `blocks_locked` already round-trips (`main/blocks.ts:69/78`); Task 1 only adds the renderer setter + store sync.
- `SettingsDropdown.tsx:27` currently shows the pane only for `scope==='view'`, else an empty placeholder — the exact route to extend.
- `viewSettingsScope` (`ViewSettingsScope.ts`) maps selection→scope; homepage currently falls to `'none'`.
- Banner heading right-click = `nexus:titleMenu` (`Banner.tsx:86`), today `'rename'|'editIcon'` only; no icon-visibility flag exists yet (must be added).
- The homepage has NO banner icon today (`Banner.tsx:76-78`); "show icon" introduces a fixed home glyph it can toggle.
- Contexts are sidecar-mode only — UI tasks (4, 5) need a sidecar nexus to exercise.
