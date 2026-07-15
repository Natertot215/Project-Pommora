# Navigation Gallery + Durable Pins + Thumbnails — Implementation Plan

> **For agentic workers:** execute task-by-task; steps use `- [ ]` checkboxes. Gates (typecheck + vitest + build) run between phases. Spec: [[Navigation Gallery + Pins — Decision Log]].

**Goal:** Add the NavPane gallery view — a responsive card grid of recents/pins with rendered-page-thumbnail cards, durable reorderable pins, and an active-item accent — plus the sync-safe pin store and capture pipeline behind it.

**Architecture:** Durable pins persist as per-pin JSON files under `.nexus/pins/` (filesystem-as-merge, no whole-array LWW loss), ordered by a numeric fractional `order`. Thumbnails are captured on entity-open via `webContents.capturePage()` in main, written under `.nexus/assets/<nexusID>/thumbnails/` and served over the existing `nexus-asset://` protocol. The gallery is a new renderer component mounted behind the existing `viewMode` toggle, reordered via the in-house `design-system/interactions` reflow engine.

**Tech Stack:** Electron 42 (main `webContents.capturePage`, chokidar watcher), React 19 renderer, Zustand store, hand-written type guards (no zod on the nav surface), Vitest.

## Global Constraints

- Main owns fs/Node; renderer reaches it only via the `window.nexus.*` contextBridge. IPC returns `{ ok: true, … } | { ok: false, error }`, never throws across the boundary.
- Colors from `design-system/tokens` as hex/`color-mix` on token vars — never raw `rgb()`. Active border = `color-mix(in srgb, var(--accent) var(--tint-secondary), transparent)`.
- No new dependency — capture uses native `nativeImage`; DND uses `design-system/interactions`; icons via `symbols`.
- Gates: `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (the only type gate, two tsc passes), `npx vitest run`, `env -u ELECTRON_RUN_AS_NODE npm run build`. Biome auto-formats on write — never hand-align.
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Stage explicit paths (parallel sessions), never `git add -A`.
- Never persist an `adopted-*` pin (adopted ids re-mint on adoption — mirror `crud/reorder.ts:22-24`).

---

## File Structure

**New**
- `src/renderer/src/Navigation/order.ts` (+ `.test.ts`) — `keyBetween(a, b)` numeric fractional order.
- `src/main/io/pinsState.ts` (+ `.test.ts`) — `readPins`/`writePin`/`removePin` over `.nexus/pins/`, `isPinEntry`, `pinFileName`.
- `src/renderer/src/Navigation/navPins.ts` (+ `.test.ts`) — pure pin-reducer helpers (`pinKey` reuse of `navKey`, `insertPin`, `reorderPinTo`, `migratePinnedRecents`).
- `src/renderer/src/NavPane/NavGallery.tsx` + `navGallery.css` — the card grid.
- `src/main/io/thumbnails.ts` — capture write/evict helpers.

**Modified**
- `src/shared/types.ts` — `PinEntry`, `PinsResult`.
- `src/main/index.ts` — `nav:loadPins`/`addPin`/`removePin`/`reorderPin`, `capture:thumbnail`.
- `src/preload/index.ts` — `nav.loadPins/addPin/removePin/reorderPin`, `capture.thumbnail`, `onNavChanged`.
- `src/main/watcher.ts` — `nav:changed` narrow push.
- `src/renderer/src/store.ts` — `pins` slice, actions, open-flow reset + migration, `applyNavChanged`.
- `src/renderer/src/Navigation/navResolve.ts` — `resolvePins`; homepage icon fix (G-1).
- `src/renderer/src/Navigation/navRecents.ts` — retire the `pinned` flag branches (F6).
- `src/renderer/src/Navigation/useNavData.ts` — `resolvedPins`; reconcile-in-`go` (A-4).
- `src/renderer/src/NavPane/NavPane.tsx` — gallery mount seam; source-capture before open.
- `src/renderer/src/Navigation/NavList.tsx` + `navList.css` — list-mode pin marker.

---

## Phase 0 — Numeric fractional order (pure util)

### Task 0: `keyBetween`

**Files:** Create `src/renderer/src/Navigation/order.ts`, `order.test.ts`.

**Produces:** `keyBetween(a: number | null, b: number | null): number` — midpoint order key. Empty→`0`; before-first→`b-1`; after-last→`a+1`; between→`(a+b)/2`.

- [ ] **Step 1 — failing test** (`order.test.ts`):
```ts
import { describe, it, expect } from 'vitest'
import { keyBetween } from './order'

describe('keyBetween', () => {
  it('seeds an empty list at 0', () => expect(keyBetween(null, null)).toBe(0))
  it('prepends below the first', () => expect(keyBetween(null, 0)).toBe(-1))
  it('appends above the last', () => expect(keyBetween(5, null)).toBe(6))
  it('takes the midpoint between two', () => expect(keyBetween(0, 1)).toBe(0.5))
  it('is strictly between its neighbors', () => {
    const m = keyBetween(0.5, 0.75)
    expect(m).toBeGreaterThan(0.5)
    expect(m).toBeLessThan(0.75)
  })
})
```
- [ ] **Step 2 — run, expect FAIL** (`npx vitest run src/renderer/src/Navigation/order.test.ts`): "keyBetween is not a function".
- [ ] **Step 3 — implement** (`order.ts`):
```ts
/** Numeric fractional order key: the value to give an item inserted between neighbors `a` and `b`
 *  (either null at a list end). Reordering rewrites only the moved item's key. Precision exhausts
 *  after ~50 consecutive midpoints in one gap — accepted ceiling (a pin set is small). */
export function keyBetween(a: number | null, b: number | null): number {
  if (a === null && b === null) return 0
  if (a === null) return (b as number) - 1
  if (b === null) return a + 1
  return (a + b) / 2
}
```
- [ ] **Step 4 — run, expect PASS.**
- [ ] **Step 5 — commit:** `git add src/renderer/src/Navigation/order.ts src/renderer/src/Navigation/order.test.ts && git commit` — `feat(nav): numeric fractional order key for pins`.

---

## Phase 1 — Durable pins data layer

### Task 1: Shared `PinEntry` type

**Files:** Modify `src/shared/types.ts` (after `NavFavorite`, ~line 336).

**Produces:** `PinEntry = NavTarget & { order: number; deleted?: boolean }`; `PinsResult = ({ ok: true; pins: PinEntry[] }) | { ok: false; error: string }`.

- [ ] **Step 1 — add the types** (no test; type-only, gated by typecheck):
```ts
/** A durable, user-ordered pin. Persisted one-file-per-pin under `.nexus/pins/` so concurrent
 *  cross-device adds never collide (filesystem-as-merge). `order` is a numeric fractional key;
 *  `deleted` is a tombstone (unpin) reaped on load. */
export type PinEntry = NavTarget & { order: number; deleted?: boolean }

/** `nav:loadPins` envelope. */
export type PinsResult = { ok: true; pins: PinEntry[] } | { ok: false; error: string }
```
- [ ] **Step 2 — typecheck:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` → 0 errors.
- [ ] **Step 3 — commit:** `src/shared/types.ts` — `feat(nav): PinEntry + PinsResult shared contract`.

### Task 2: Main pins store (`pinsState.ts`)

**Files:** Create `src/main/io/pinsState.ts`, `pinsState.test.ts`. Reference: mirror `navState.ts` (validators, `serializeOnFile`, `writeJson`, `readJsonObject`) + the per-file dir read from `readNexus.ts:200-213`.

**Interfaces — Produces:**
- `pinFileName(t: NavTarget): string` — `navKey` with `:`→`-` (homepage → `homepage`).
- `readPins(root: string): Promise<PinEntry[]>` — read `.nexus/pins/*.json`, validate, drop tombstones + malformed (log, don't crash).
- `writePin(root, pin: PinEntry): Promise<void>` — atomic write `.nexus/pins/<pinFileName>.json`.
- `removePin(root, t: NavTarget, order: number): Promise<void>` — tombstone-write `{ ...t, order, deleted: true }`.

- [ ] **Step 1 — failing test** (`pinsState.test.ts`, mkdtemp template from `navState.test.ts:1-17`):
```ts
import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import type { PinEntry } from '@shared/types'
import { readPins, writePin, removePin, pinFileName } from './pinsState'

let root: string
beforeEach(async () => { root = await mkdtemp(join(tmpdir(), 'pom-pins-')) })
afterEach(async () => { await rm(root, { recursive: true, force: true }) })

const pin = (over: Partial<PinEntry> = {}): PinEntry => ({ kind: 'collection', id: 'c1', order: 0, ...over }) as PinEntry

it('round-trips a pin', async () => {
  await writePin(root, pin())
  expect(await readPins(root)).toEqual([pin()])
})
it('sanitizes the colon out of the filename', () => {
  expect(pinFileName({ kind: 'collection', id: 'c1' })).toBe('collection-c1')
  expect(pinFileName({ kind: 'homepage' })).toBe('homepage')
})
it('a tombstoned pin is dropped on read', async () => {
  await writePin(root, pin())
  await removePin(root, { kind: 'collection', id: 'c1' }, 0)
  expect(await readPins(root)).toEqual([])
})
it('reads nothing from a missing dir', async () => { expect(await readPins(root)).toEqual([]) })
```
- [ ] **Step 2 — run, expect FAIL** (module missing).
- [ ] **Step 3 — implement** (`pinsState.ts`):
```ts
import { readdir } from 'node:fs/promises'
import { join } from 'node:path'
import { isPlainObject } from '@shared/propertyValue'
import type { NavTarget, PinEntry } from '@shared/types'
import { nexusDir } from '../paths'
import { mkdir } from 'node:fs/promises'
import { readJsonObject, writeJson } from './atomicWrite'
import { serializeOnFile } from './fileLock'

const NAV_KINDS = new Set(['homepage', 'context', 'collection', 'set', 'page', 'task', 'event'])
const pinsDir = (root: string): string => join(nexusDir(root), 'pins')

/** navKey with the path-illegal colon swapped (collision-free: kinds are `-`-free, ids are ULID or
 *  `adopted-<hex>` and we never split the filename back apart). Homepage has no id → bare `homepage`. */
export function pinFileName(t: NavTarget): string {
  return 'id' in t ? `${t.kind}-${t.id}` : t.kind
}

function isPinEntry(v: unknown): v is PinEntry {
  if (!isPlainObject(v)) return false
  const kind = v.kind
  if (typeof kind !== 'string' || !NAV_KINDS.has(kind)) return false
  if (kind !== 'homepage' && typeof v.id !== 'string') return false
  if ((kind === 'set' || kind === 'page') && typeof v.path !== 'string') return false
  if (typeof v.order !== 'number') return false
  return v.deleted === undefined || typeof v.deleted === 'boolean'
}

export async function readPins(root: string): Promise<PinEntry[]> {
  let names: string[]
  try {
    names = (await readdir(pinsDir(root))).filter((n) => n.endsWith('.json') && !n.endsWith('.tmp'))
  } catch {
    return []
  }
  const out: PinEntry[] = []
  for (const name of names) {
    const obj = await readJsonObject(join(pinsDir(root), name))
    if (obj === null) continue // in-flight / unreadable — skip, don't shrink silently on parse-null
    if (!isPinEntry(obj)) continue
    if (obj.deleted) continue // tombstone — reaped from the in-memory set
    out.push(obj)
  }
  return out.sort((x, y) => x.order - y.order || pinFileName(x).localeCompare(pinFileName(y)))
}

function writeAt(root: string, name: string, value: PinEntry): Promise<void> {
  const path = join(pinsDir(root), `${name}.json`)
  return serializeOnFile(path, async () => {
    await mkdir(pinsDir(root), { recursive: true })
    await writeJson(path, value)
  })
}

export async function writePin(root: string, pin: PinEntry): Promise<void> {
  await writeAt(root, pinFileName(pin), pin)
}

export async function removePin(root: string, t: NavTarget, order: number): Promise<void> {
  await writeAt(root, pinFileName(t), { ...t, order, deleted: true } as PinEntry)
}
```
> Verify at execution: `readJsonObject` returns `null` on missing/corrupt (mirror its `readJsonArray` sibling, `atomicWrite.ts:74-81`); `nexusDir`/`serializeOnFile` import paths match `navState.ts`. Adjust imports to the real exports.
- [ ] **Step 4 — run, expect PASS.**
- [ ] **Step 5 — commit:** `src/main/io/pinsState.ts` + test — `feat(nav): per-pin-file store under .nexus/pins`.

### Task 3: Pins IPC + preload

**Files:** Modify `src/main/index.ts` (after `nav:saveFavorites`, ~line 302; import at line 27), `src/preload/index.ts` (nav object ~285-290; type import line 3).

**Produces (preload):** `window.nexus.nav.loadPins()`, `.addPin(pin)`, `.removePin(target, order)`, `.reorderPin(pin)` — all `{ok}` envelopes / `PinsResult`.

- [ ] **Step 1 — main handlers** (mirror `nav:load`/`nav:saveFavorites` verbatim shape, envelope + `sessionRoot()` guard):
```ts
ipcMain.handle('nav:loadPins', async (): Promise<PinsResult> => {
  const root = sessionRoot()
  if (root === null) return { ok: false, error: 'No nexus open' }
  try { return { ok: true, pins: await readPins(root) } }
  catch (e) { return { ok: false, error: e instanceof Error ? e.message : String(e) } }
})
ipcMain.handle('nav:addPin', async (_e, pin: unknown) => {
  try {
    const root = sessionRoot(); if (root === null) return { ok: false, error: 'No nexus is open.' }
    if (!isPlainObject(pin)) return { ok: false, error: 'Pin must be an object.' }
    await writePin(root, pin as PinEntry); return { ok: true }
  } catch (e) { return { ok: false, error: e instanceof Error ? e.message : String(e) } }
})
ipcMain.handle('nav:reorderPin', async (_e, pin: unknown) => { /* identical body to addPin */ })
ipcMain.handle('nav:removePin', async (_e, target: unknown, order: unknown) => {
  try {
    const root = sessionRoot(); if (root === null) return { ok: false, error: 'No nexus is open.' }
    if (!isPlainObject(target) || typeof order !== 'number') return { ok: false, error: 'Bad remove-pin args.' }
    await removePin(root, target as NavTarget, order); return { ok: true }
  } catch (e) { return { ok: false, error: e instanceof Error ? e.message : String(e) } }
})
```
Extend imports: add `readPins, writePin, removePin` to a new `from './io/pinsState'` line; add `PinEntry, PinsResult` to the `@shared/types` import; `isPlainObject` from `@shared/propertyValue`.
- [ ] **Step 2 — preload methods** (extend the `nav` object, comma after `saveFavorites`):
```ts
    loadPins: (): Promise<PinsResult> => ipcRenderer.invoke('nav:loadPins'),
    addPin: (pin: PinEntry): Promise<{ ok: true } | { ok: false; error: string }> => ipcRenderer.invoke('nav:addPin', pin),
    reorderPin: (pin: PinEntry): Promise<{ ok: true } | { ok: false; error: string }> => ipcRenderer.invoke('nav:reorderPin', pin),
    removePin: (target: NavTarget, order: number): Promise<{ ok: true } | { ok: false; error: string }> => ipcRenderer.invoke('nav:removePin', target, order)
```
Add `NavTarget, PinEntry, PinsResult` to the preload `@shared/types` import (line 3).
- [ ] **Step 3 — typecheck** → 0. (No unit test — thin wrappers; the store test in Task 5 exercises the round-trip through a mocked bridge.)
- [ ] **Step 4 — commit:** `index.ts` + `preload/index.ts` — `feat(nav): pins IPC + preload bridge`.

### Task 4: Pure pin reducers (`navPins.ts`)

**Files:** Create `src/renderer/src/Navigation/navPins.ts`, `navPins.test.ts`. Reuse `navKey` from `navRecents.ts`; `keyBetween` from `order.ts`.

**Produces:**
- `pinFor(target, pins): PinEntry` — new PinEntry with `order = keyBetween(lastOrder, null)` (append to end).
- `reorderTo(pins: PinEntry[], activeKey, overKey): PinEntry | null` — the moved pin with a recomputed `order` (midpoint of its new neighbors), or null if no-op.
- `migratePinnedRecents(recents: RecentEntry[]): PinEntry[]` — legacy `pinned:true` → PinEntry[] with spaced integer orders.

- [ ] **Step 1 — failing test** (`navPins.test.ts`):
```ts
import { describe, it, expect } from 'vitest'
import type { PinEntry, RecentEntry } from '@shared/types'
import { pinFor, reorderTo, migratePinnedRecents } from './navPins'
import { navKey } from './navRecents'

const p = (id: string, order: number): PinEntry => ({ kind: 'page', id, path: `/${id}`, order }) as PinEntry

it('appends above the current max order', () => {
  const next = pinFor({ kind: 'page', id: 'z', path: '/z' }, [p('a', 0), p('b', 1)])
  expect(next.order).toBeGreaterThan(1)
})
it('reorders to a midpoint between new neighbors', () => {
  const moved = reorderTo([p('a', 0), p('b', 1), p('c', 2)], navKey({ kind: 'page', id: 'c' }), navKey({ kind: 'page', id: 'a' }))
  expect(moved!.order).toBeLessThan(0) // dropped before 'a'
})
it('migrates pinned recents to ordered pins', () => {
  const recents: RecentEntry[] = [{ kind: 'page', id: 'a', path: '/a', pinned: true }, { kind: 'page', id: 'b', path: '/b' }, { kind: 'context', id: 'x', pinned: true }]
  const pins = migratePinnedRecents(recents)
  expect(pins.map((x) => navKey(x))).toEqual(['page:a', 'context:x'])
  expect(pins[0].order).toBeLessThan(pins[1].order)
})
```
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (`navPins.ts`): compose `navKey` + `keyBetween`; `reorderTo` finds active/over indices in the current sorted list, computes the target slot's neighbors, returns `{ ...moved, order: keyBetween(before, after) }`; `migratePinnedRecents` filters `r.pinned`, strips the flag, assigns `order: i` (integer spacing).
- [ ] **Step 4 — run, expect PASS.**
- [ ] **Step 5 — commit:** `navPins.ts` + test — `feat(nav): pure pin reducers (append, reorder-midpoint, migrate)`.

### Task 5: Store pins slice + open-flow reset + migration

**Files:** Modify `src/renderer/src/store.ts` — interface (~151-172), initializer (~437-438), actions (~439-465), open flow (~291-299).

**Produces (store):** `pins: PinEntry[]`; `pinTarget(target)`, `unpinTarget(key)`, `reorderPin(activeKey, overKey)`, `loadPins()`. `isPinned(key)` selector via `pins.some`.

- [ ] **Step 1 — failing test** (extend `store` test or a new `navPins.store.test.ts` with the bridge mocked): pinning a target appends it to `pins` and calls `window.nexus.nav.addPin`; unpin calls `removePin` and drops it; reorder recomputes order + calls `reorderPin`.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement** (mirror `addFavorite`/`removeFavorite` shape):
```ts
pins: [],
pinTarget: (target) => {
  if (target.kind === 'task' || target.kind === 'event') return
  if ('id' in target && String(target.id).startsWith('adopted-')) return // never persist adopted ids
  const key = navKey(target)
  if (get().pins.some((p) => navKey(p) === key)) return
  const pin = pinFor(target, get().pins)
  set({ pins: [...get().pins, pin].sort(byOrder) })
  void window.nexus.nav.addPin(pin)
},
unpinTarget: (key) => {
  const pin = get().pins.find((p) => navKey(p) === key)
  if (!pin) return
  set({ pins: get().pins.filter((p) => navKey(p) !== key) })
  void window.nexus.nav.removePin(cleanTargetOf(pin), pin.order)
},
reorderPin: (activeKey, overKey) => {
  const moved = reorderTo(get().pins, activeKey, overKey)
  if (!moved) return
  set({ pins: get().pins.map((p) => (navKey(p) === activeKey ? moved : p)).sort(byOrder) })
  void window.nexus.nav.reorderPin(moved)
},
loadPins: async () => {
  const res = await window.nexus.nav.loadPins().catch(() => null)
  if (res?.ok) set({ pins: res.pins })
},
```
`byOrder` = `(a,b)=>a.order-b.order || navKey(a).localeCompare(navKey(b))`; `cleanTargetOf` strips `order`/`deleted` down to `NavTarget`.
- [ ] **Step 4 — open-flow reset + migration** (in `load()` open case, ~291-299): after loading recents/favorites, `const pinsRes = await window.nexus.nav.loadPins()`; if `pinsRes.ok && pinsRes.pins.length` set `pins`; **else** run `migratePinnedRecents(nav.recents)` → write each via `nav.addPin` → set `pins` (gated on a `.nexus/pins/.migrated` marker; if the marker exists, skip migration and set `pins: []`). Reset `pins: []` on the failure branch.
- [ ] **Step 5 — run gates, commit:** `store.ts` — `feat(nav): durable pins store slice + open-flow load/migrate`.

### Task 6: `resolvePins` + retire the `pinned` flag + A-4 reconcile + homepage icon

**Files:** `navResolve.ts` (add `resolvePins`; G-1 homepage icon), `navRecents.ts` (remove `pinned` branches — F6), `useNavData.ts` (`resolvedPins`; reconcile-in-`go` — A-4).

- [ ] **Step 1 — `resolvePins`** (`navResolve.ts`, mirror `resolveFavorites`): `export function resolvePins(index, pins: PinEntry[]): ResolvedNav[]` = `pins.map(p => resolveWith(index, p)).filter(Boolean)` — already order-sorted upstream. Add a test in `navResolve.test.ts`.
- [ ] **Step 2 — G-1 homepage icon** (`navResolve.ts:51`): replace hardcoded `{ icon: 'house' }` with the homepage's assigned icon — `iconNameOr(tree.homepage?.icon, defaultEntityIcon('homepage', di))` (verify the homepage icon field name against `types.ts` at execution; fall back to `'house'` only if truly unset). Test: a homepage with a custom icon resolves to it.
- [ ] **Step 3 — retire `pinned` (F6):** delete `togglePinned` + the `pinned` exemption branch in `capRecents` + the pin-float in `resolveRecents` (recents now render pure MRU; pins are their own list). Update the three functions' tests (`navRecents.test.ts`, `navResolve.test.ts`) — drop pin-float assertions, keep dedupe/cap. Grep for `togglePin`/`pinned` consumers and remove `store.togglePin`.
- [ ] **Step 4 — A-4 reconcile-in-`go`** (`useNavData.ts:59`):
```ts
const go = useCallback((target: NavTarget, onDone?: () => void): void => {
  if (!isTreeTarget(target)) return
  const fresh = tree ? reconcileSelection(tree, target) : target
  if (fresh.kind === 'none') return // deleted between render and click — bail, don't open a dead path
  void select(fresh as NavTarget)
  onDone?.()
}, [select, tree])
```
Import `reconcileSelection` from `../selection`; add `resolvedPins` to `useNavData`'s return (`useMemo(() => resolveIndex ? resolvePins(resolveIndex, pins) : [], [resolveIndex, pins])`, reading `pins` from the store).
- [ ] **Step 5 — run gates, commit:** the four files + tests — `feat(nav): resolvePins, retire pinned flag, reconcile-on-click, homepage icon`.

**GATE 1 (data layer):** `typecheck` 0 · `vitest` green · `build` 0. Manual: pin/unpin/reorder a couple entities live (via a temporary dev hook or the gallery once Phase 4 lands — defer live check to after Phase 4 if no UI yet). Checkpoint with Nathan.

---

## Phase 2 — Live nav-refresh (F2)

### Task 7: `nav:changed` narrow push

**Files:** `src/main/watcher.ts` (classify + `pushNav`), `src/preload/index.ts` (`onNavChanged`), `src/renderer/src/store.ts` (`applyNavChanged` + subscribe).

**Produces:** `window.nexus.onNavChanged(cb: (nav: { recents; favorites; pins }) => void)`; store re-reads nav on the event without a tree walk.

- [ ] **Step 1 — watcher branch** (`watcher.ts` `onEvent`, ~66): classify `relative(root, path).split(sep)` — if `segs[0] === '.nexus'` and `segs[1] ∈ { 'navRecents.json', 'navFavorites.json', 'pins' }`, fire a separate debounced `pushNav(root, win)` that reads `readNavState(root)` + `readPins(root)` and `win.webContents.send('nav:changed', { ...navState, pins })`. Reuse the `isRecentWrite` early-return (own writes don't echo) and the `sessionRoot() !== root || win.isDestroyed()` guard.
- [ ] **Step 2 — preload** `onNavChanged` mirroring `onNexusChanged` (`preload/index.ts:375-381`).
- [ ] **Step 3 — store** `applyNavChanged(nav)` = `set({ recents: nav.recents, favorites: nav.favorites, pins: nav.pins })`; subscribe once in the app-init effect that already wires `onNexusChanged` (find it — likely `App.tsx`/store init).
- [ ] **Step 4 — test:** `watcher.ts` classification is pure enough to unit-test the segment matcher; extract `isNavPath(root, path): boolean` and test it (matches the three, rejects a page `.md`, rejects `.nexus/thumbnails`). Gate + commit — `feat(nav): live nav-refresh on .nexus/pins|navRecents|navFavorites`.

**GATE 2:** gates green. Manual (needs two windows or an external edit): edit `.nexus/pins/*.json` externally → the open app reflects it without ⌘R. Checkpoint.

---

## Phase 3 — Thumbnail capture pipeline

### Task 8: Capture write + evict helpers (`thumbnails.ts`)

**Files:** Create `src/main/io/thumbnails.ts`. Grounded surfaces: `atomicWriteBinary(path, Buffer)` (atomicWrite.ts:20); `ensureIdentity(root): Promise<{id, created}>` (identity.ts:30) → nexusId; asset URL `nexus-asset://nexus/<rel>` (index.ts:143, scheme `nexus-asset`); window handle `mainWindow` / `BrowserWindow.fromWebContents(e.sender)` (index.ts:172,215). Capture rect = renderer's `.content-pane` element (App.tsx:136 — the detail pane, H-3) `getBoundingClientRect()`. Reuse `pinFileName`-style sanitize (navKey `:`→`-`) for the filename.

**Produces:**
- `thumbRel(nexusId, key): string` — `.nexus/assets/<nexusId>/thumbnails/<key>.jpg`.
- `captureThumbnail(win, root, key, rect): Promise<string>` — `win.webContents.capturePage()` → `crop(rect × scaleFactor)` → `resize({width})` → `toJPEG(78)` → `atomicWriteBinary` → return `nexus-asset://nexus/<rel>`.
- `evictThumbnails(root, liveKeys: string[]): Promise<void>` — delete `<thumbnails>/*.jpg` whose key ∉ liveKeys.

- [ ] **Step 1 — implement** (no unit test for `capturePage` itself — it needs a live window; test `thumbRel` + `evictThumbnails` set logic against a temp dir):
```ts
export async function captureThumbnail(win, root, key, rect, scaleFactor): Promise<string | null> {
  const img = await win.webContents.capturePage() // full page — avoids the HiDSPI rect-crop bug
  const dev = { x: Math.round(rect.x*scaleFactor), y: Math.round(rect.y*scaleFactor), width: Math.round(rect.width*scaleFactor), height: Math.round(rect.height*scaleFactor) }
  const buf = img.crop(dev).resize({ width: 480, quality: 'best' }).toJPEG(78)
  const nexusId = await ensureIdentity(root)
  const rel = thumbRel(nexusId, key)
  await mkdir(dirname(join(root, rel)), { recursive: true })
  await atomicWriteBinary(join(root, rel), buf)
  return `nexus-asset://nexus/${rel}`
}
```
- [ ] **Step 2 — test** `thumbRel` + `evictThumbnails` (mkdtemp, write dummy jpgs, evict, assert survivors). Gate + commit — `feat(nav): thumbnail capture + membership eviction helpers`.

### Task 9: `capture:thumbnail` IPC + preload + renderer trigger

**Files:** `index.ts` (handler), `preload/index.ts` (`capture` object), `store.ts` (capture trigger).

**Produces:** `window.nexus.capture.thumbnail(key, rect, scaleFactor)`; store fires it on settle.

- [ ] **Step 1 — handler:** `ipcMain.handle('capture:thumbnail', async (e, key, rect, scaleFactor) => { const win = BrowserWindow.fromWebContents(e.sender); ... return { ok: true, path } })`. `scaleFactor` from the renderer (`window.devicePixelRatio`) or `screen.getPrimaryDisplay().scaleFactor`.
- [ ] **Step 2 — preload** `capture: { thumbnail: (key, rect, scaleFactor) => ipcRenderer.invoke('capture:thumbnail', key, rect, scaleFactor) }`.
- [ ] **Step 3 — renderer trigger:** a `captureCurrent()` helper — measures the detail-pane element rect (`getBoundingClientRect()`), waits `document.fonts.ready` + double-rAF, then calls `capture.thumbnail(navKey(selection), rect, devicePixelRatio)`. Debounce ~200ms; **skip when `pageStatus === 'error'`**; fire once per settled `select` (a `useEffect` on `selection`+`pageStatus === 'ready'`, guarded off scroll/HMR). Identify the pane element (the explorer flagged `getBoundingClientRect` needs a stable wrapper — use the `DetailPane` root; confirm its ref/class at execution).
- [ ] **Step 4 — source-capture-before-open (B-2b/#1):** in the `navOpen: false→true` transition — since **both** `openNav` and `toggleNav` flip it — factor a shared `beginOpenNav()` that fires `captureCurrent()` for the current `selection` FIRST, then `set({ navOpen: true })`. Both callers route through it.
- [ ] **Step 5 — eviction wire:** after a recents roll-off (`capRecents` in the recents-record path) or on nav load, compute live keys = `recents ∪ pins` (by `pinFileName`) and call a `capture.evict(liveKeys)` IPC (add a tiny `nav:evictThumbs` handler → `evictThumbnails`). Gate + commit — `feat(nav): capture-on-open thumbnail pipeline + eviction`.

**GATE 3:** gates green. Manual (Nathan, live): open a few pages → thumbnails write under `.nexus/assets/<id>/thumbnails/`; open NavPane → the source page's thumb refreshes; confirm no capture on error pages; confirm captures don't fire on scroll. Checkpoint — this is the highest-risk phase (capture timing, rect accuracy, blank/overlay frames).

---

## Phase 4 — Gallery UI

### Task 10: `NavGallery` component + CSS  *(RECONCILED with Figma 996:3750 + Nathan)*

**Files:** Create `src/renderer/src/NavPane/NavGallery.tsx`, `navGallery.css`. Reference: `interactions/Surfaces.tsx:38-53` (grid reflow), `Sidebar/Ribbon.tsx:57-78` (reorder+persist), `NavList.tsx` (OverflowScroll title/path crumb map), `interactions.css:176-186` (grid CSS). DND seam = `@renderer/design-system/interactions/drag` (`SortableZone`, `useDragItem`, `reorder`, key-based `onReorder(activeId, overId)`).

**Card anatomy (H-2, confirmed):** a card is **thumbnail (top ~2/3) over a text area (bottom ~1/3)**.
- **Thumbnail:** the detail-pane screenshot, 3:2-ish landscape, `10px` top-radius, hairline separator border. `<img loading="lazy" src={thumbUrl(tree.nexus.id, key)} onError={→placeholder}>` — the URL is deterministic (`nexus-asset://nexus/.nexus/assets/<nexusId>/thumbnails/<sanitized-key>.jpg` + `?v=<thumbVersion>` cache-bust); `onError` swaps a placeholder tile (entity `Icon` on `--accent-fill`). Homepage thumbnail: its captured pane; homepage row/text-glyph icon = `tree.nexus.profileIcon` (already resolved in `ResolvedNav.icon`).
- **Pin overlay:** accent pin **top-left ON the thumbnail** — solid `--accent` `<Icon name="pin">` when pinned; a hover-revealed faint pin on unpinned cards → `onClick` `pinTarget`. (`pin` renders via the Lucide fallback; curate `pin: Pin` in `symbols/index.tsx` if desired.)
- **Text area (~1/3):** title row (`<Icon name={it.icon} size={14}>` + `<OverflowScroll className="gallery-card-title">` label-primary) over location row (`<OverflowScroll className="gallery-card-loc">` reusing NavList's `it.path` crumb map — label-secondary text + tertiary crumb icons). Independent lines, eclipse-scroll via `--eclipse-fade`.
- **Active card:** when `useSession(s=>s.selection)` matches `it.target` (kind+id via `navKey`) → `.is-active` accent-tint border `color-mix(in srgb, var(--accent) var(--tint-secondary), transparent)`.

- [ ] **Step 1 — component:** `<SortableZone items={pins.map(p=>p.key)} layout="grid" onReorder={(a,o)=>reorderPin(a,o)}>` wrapping the pinned cards (each `useDragItem(it.key)` → spread `style`+`handle`), then the recents cards after (non-draggable, `pinnedKeys`-deduped already by `useNavData`). One `Card` subcomponent, `pinned` prop drives the pin state + draggability. `onSelect={goClose}`.
- [ ] **Step 2 — CSS** (`navGallery.css`, co-located): **dynamic flow** = `.nav-gallery { display:grid; grid-template-columns: repeat(auto-fill, minmax(var(--card-min,150px), 1fr)); gap: var(--card-gap-v,12px) var(--card-gap-h,12px) }` (knobs: `--card-min`, `--card-gap-h/v`); card `border-radius:10px`, `border:1px solid var(--separator-border)`; thumbnail `aspect-ratio:3/2; object-fit:cover; object-position:top`; text area padded; `.is-active` accent border; pin `position:absolute; top/left; color:var(--accent)`; unpinned pin `opacity:0` → `.nav-gallery-card:hover .pin{opacity:1}`. Radius from `size.css.ts` 10px step; mirror `navList.css` title/loc tokens.
- [ ] **Step 3 — mount seam** (`NavPane.tsx:153-159`): branch the recents (non-search) case on `viewMode` → `<NavGallery pins={resolvedPins} items={resolvedRecents} onSelect={goClose} />` else `<NavList>`. Add `resolvedPins` from `useNavData`. **Preserve Nathan's uncommitted `WIN` knob edit in NavPane.tsx.**
- [ ] **Step 4 — verify:** typecheck + build; **Nathan live-checks** (dynamic-flow columns, thumbnails, reorder reflow, active accent, pin/unpin). Commit — `feat(nav): NavGallery card grid with reorder + active accent`.

### Task 11: List-mode pin marker

**Files:** `NavList.tsx`, `navList.css`.

- [ ] **Step 1:** in list rows, when the row's key is pinned (pass `pinnedKeys: Set<string>` or read the store), render an accent pin `<Icon name="pin" size={12} />` in the `--navpane-inset` gutter (before the entity icon). CSS: `.nav-item-pin { color: var(--accent) }`.
- [ ] **Step 2:** typecheck + build; Nathan live-checks. Commit — `feat(nav): list-mode accent pin marker`.

**GATE 4 (UIX):** post-functional UIX review of the working gallery (Review-Discipline: mandatory before closeout). Nathan live-passes layout/feel; a UIX pass on the actual UI. Fold findings.

---

## Phase 5 — Docs + closeout

### Task 12: Reconcile docs

- [ ] Update [[Navigation]]: gallery + pin-marker move from "open work" to shipped; describe durable per-pin-file pins, the thumbnail pipeline, active-accent; note NavMenu still undecided. Fold durable-pins into the Navigation-layer bullets (pins are no longer "temp-pins on the recents stream").
- [ ] `History.md`: newest-first entry — the gallery/pins/thumbnail arc + the locked decisions (per-pin files, capture-on-open, synced under assets).
- [ ] Run `/handoff`.
- [ ] Commit docs (`feat`/`docs`), explicit paths.

---

## Self-Review (against the spec)

- **Coverage:** A (pins model) → T1–T6; A-4 reconcile → T6; A-5 per-pin files + order + tiebreak → T0,T2,T4; A-5b tombstone/malformed/precision → T2 (tombstone read-skip, malformed log-skip, ceiling accepted in `order.ts`); B (thumbnails) → T8,T9; B-2b source-before-open → T9.4; C (all kinds) → T10 (cards for every `ResolvedNav`); D (reflow reorder) → T10; E (active accent) → T10; F (list pin marker) → T11; G (homepage icon) → T6.2; I-3c live refresh → T7; J-1..J-5 → nexus-scoped assets path (T8), render-prune (resolveWith already), migration sentinel (T5.4), tap-vs-drag (SortableZone handles it), lazy-load (T10). Eviction → T8,T9.5.
- **Placeholder scan:** the two "verify at execution" notes (readJsonObject null-behavior; DetailPane ref) are grounding confirmations, not deferred logic — resolve them by reading the cited file when the task runs.
- **Type consistency:** `PinEntry`/`PinsResult` (T1) used identically in T2/T3/T5; `navKey`/`pinFileName` distinction is deliberate (in-memory key vs filename); `keyBetween` numeric throughout.
- **Open risk carried:** F1 (unpin-vs-reorder resurrection) is handled by tombstones (T2 `removePin` writes `deleted:true`; T2 `readPins` skips them) — but a tombstone is never reaped from disk here; a periodic reap is a Prospect (tombstones are tiny). Noted, not blocking.
