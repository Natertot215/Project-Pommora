## Persistent Thumbnail Cache — Implementation Plan

> **For agentic workers:** implement task-by-task; each task ends green before the next. Steps use checkbox (`- [ ]`) syntax. Nathan executes inline. Realizes Cards Decision Log **B-6** and the checklist's "persistent thumbnail cache" item — a Navigation-layer fix that also cures NavGallery covers, not Cards-only.

**Goal:** Stop navigation/cover thumbnails from vanishing over time — make the cache amend-only, and replace the recents∪pins window-eviction with existence-pruning (drop only thumbnails whose entity no longer exists).

**Architecture:** The cache already amends — `captureThumbnail` atomic-overwrites the keyed `.jpg`. The *only* deletion is `evictThumbnails(root, liveKeys)`, driven from `store.ts` `evictThumbs()` with `liveKeys = recents ∪ pins` — a shrinking window, so any cover outside your recent set gets deleted. Two changes: **(1)** widen the key set to **every navKey that exists in the tree** (a new pure `existingNavKeys(tree)`) *unioned with* recents∪pins — the union is a fault guard: the tree comes from a fs walk that reads a subtree as **empty** on a transient error (`readNexus.ts:174`/`:222`), and deleting "existence" off a false-empty read would re-create the vanish bug, so recents/pins backstop a just-visited cover. **(2)** **Gate the trigger to genuine nexus-open** — today it rides every structural-mutation refetch (`load()` at `store.ts:1625`). `evictThumbnails` and the IPC stay untouched. A live entity's key is always present (via the tree, or recents/pins as backstop), so its cover is never deleted; only orphans (entities gone from *both* the tree and recents) get cleaned, once per open.

**Tech Stack:** React 19 + TypeScript renderer · Zustand store · Electron 42 main (owns fs) · Vitest.

**Status:** Review-certified — one build-breaking round folded (the union fault-guard + open-gating below are the round-1 fixes; the briefed lazy-load fear was disproven — `readNexus` is a fully eager recursive walk).

### Global Constraints

- **Only type gate:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (the build strips types unchecked). Tests: `npx vitest run`. Build: `env -u ELECTRON_RUN_AS_NODE npm run build`. All commands run from `Pommora/`. Read the summary line — a piped exit code lies; `set -o pipefail` when piping.
- **Biome formats on write** (single-quote, no semicolons) via a PostToolUse hook — never hand-format; an edit failing on whitespace means Biome reformatted, so re-read and retry.
- **`navKey` is the single key-format source.** Never re-encode `kind:id` anywhere else — duplicating it is the two-writers defect class that has bitten this exact subsystem (capture marker vs thumbnail file).
- **No new IPC.** Reuse `window.nexus.capture.evict` → `nav:evictThumbs` → `evictThumbnails`. Main stays untouched except a comment.
- **Renderer never touches fs.** The tree walk is pure renderer logic over already-loaded state; deletion stays in main.
- **Dev app runs against the real Nexus** — for the live check, drive only opens/reads, never the editor on an existing page.

**Amend-only is already true — do NOT add it.** `captureThumbnail` (`src/main/io/thumbnails.ts:73`) overwrites the keyed file every capture. No capture-path change is in scope; the fix is entirely about which keys survive eviction.

---

### Task 1: `existingNavKeys(tree)` — the existence key set

The pure, testable core. Enumerates every navKey a thumbnail can be keyed to. **Completeness is the correctness property:** capture only ever fires on a `SelectionState` (`useNavThumbnails`), whose kinds are exactly `homepage · context · collection · set · page` — a closed set. Enumerate all of those from the tree and existence-pruning can never delete a live cover; under-collect one kind and its live thumbnail dies (the vanish bug, back). The one trap: **contexts (areas/topics/projects) all select as `context:<id>`** — their key comes from `navKey`'s context member, never their node `kind`.

**Files:**
- Create: `src/renderer/src/Navigation/treeNavKeys.ts`
- Test: `src/renderer/src/Navigation/treeNavKeys.test.ts`

**Interfaces:**
- Consumes: `navKey` from `./navRecents`; `NexusTree`, `CollectionNode`, `SetNode` from `@shared/types`.
- Produces: `existingNavKeys(tree: NexusTree): string[]` — every navKey present in the tree (`homepage` singleton always included; contexts as `context:<id>`).

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from 'vitest'
import type {
  AreaNode,
  CollectionNode,
  NexusTree,
  PageNode,
  ProjectNode,
  SetNode,
  TopicNode,
} from '@shared/types'
import { existingNavKeys } from './treeNavKeys'

const page = (id: string): PageNode => ({ id, kind: 'page', title: id, path: `${id}.md` })
const set = (id: string, pages: PageNode[] = [], sets: SetNode[] = []): SetNode => ({
  id,
  kind: 'set',
  title: id,
  path: id,
  pages,
  sets,
})
const collection = (id: string, pages: PageNode[] = [], sets: SetNode[] = []): CollectionNode => ({
  id,
  kind: 'collection',
  title: id,
  path: id,
  pages,
  sets,
})
const area = (id: string): AreaNode => ({ id, kind: 'area', title: id, path: id })
const topic = (id: string): TopicNode => ({ id, kind: 'topic', title: id, path: id })
const project = (id: string): ProjectNode => ({ id, kind: 'project', title: id, path: id })

// Only the slices existingNavKeys reads; the rest of NexusTree is irrelevant to this unit.
const tree = (over: Partial<NexusTree>): NexusTree =>
  ({
    contexts: { areas: [], topics: [], projects: [] },
    collections: [],
    userSections: [],
    ...over,
  }) as unknown as NexusTree

describe('existingNavKeys', () => {
  it('walks collections, nested sets, and pages at every depth', () => {
    const t = tree({
      collections: [
        collection('c1', [page('p1')], [set('s1', [page('p2')], [set('s2', [page('p3')])])]),
      ],
    })
    const keys = new Set(existingNavKeys(t))
    for (const k of [
      'collection:c1',
      'page:p1',
      'set:s1',
      'page:p2',
      'set:s2',
      'page:p3',
    ])
      expect(keys.has(k)).toBe(true)
  })

  it('keys contexts as context:<id>, never their node kind', () => {
    const t = tree({ contexts: { areas: [area('a1')], topics: [topic('t1')], projects: [project('pr1')] } })
    const keys = new Set(existingNavKeys(t))
    expect(keys.has('context:a1')).toBe(true)
    expect(keys.has('context:t1')).toBe(true)
    expect(keys.has('context:pr1')).toBe(true)
    expect(keys.has('area:a1')).toBe(false) // the trap: node kind is 'area', selection key is 'context'
  })

  it('includes collections nested under user sections', () => {
    const t = tree({ userSections: [{ id: 'u1', label: 'U', collections: [collection('c2', [page('p4')])] }] })
    const keys = new Set(existingNavKeys(t))
    expect(keys.has('collection:c2')).toBe(true)
    expect(keys.has('page:p4')).toBe(true)
  })

  it('always includes the id-less homepage singleton', () => {
    expect(existingNavKeys(tree({}))).toContain('homepage')
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/renderer/src/Navigation/treeNavKeys.test.ts`
Expected: FAIL — `existingNavKeys` is not exported / module not found.

- [ ] **Step 3: Write the implementation**

`src/renderer/src/Navigation/treeNavKeys.ts`:

```ts
import type { CollectionNode, NexusTree, SetNode } from '@shared/types'
import { navKey } from './navRecents'

/** Every navKey that currently exists in the tree — the complete set an entity's thumbnail can be
 *  keyed to. Capture fires only on a SelectionState (`useNavThumbnails`), whose kinds are exactly
 *  homepage · context · collection · set · page, so enumerating those from the tree is the closed set:
 *  existence-pruning against it drops only a deleted entity's orphan, never a live cover. Contexts
 *  (areas/topics/projects) all select as `context:<id>`, so their key comes from navKey's context
 *  member — never their node kind. */
export function existingNavKeys(tree: NexusTree): string[] {
  const keys: string[] = ['homepage'] // the id-less singleton — navKey({ kind: 'homepage' })
  const walk = (c: CollectionNode | SetNode): void => {
    keys.push(
      c.kind === 'collection'
        ? navKey({ kind: 'collection', id: c.id })
        : navKey({ kind: 'set', id: c.id, path: c.path }),
    )
    for (const p of c.pages) keys.push(navKey({ kind: 'page', id: p.id, path: p.path }))
    for (const s of c.sets ?? []) walk(s)
  }
  for (const c of tree.collections) walk(c)
  for (const u of tree.userSections) for (const c of u.collections) walk(c)
  for (const ctx of [...tree.contexts.areas, ...tree.contexts.topics, ...tree.contexts.projects])
    keys.push(navKey({ kind: 'context', id: ctx.id }))
  return keys
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/renderer/src/Navigation/treeNavKeys.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 5: Typecheck**

Run: `env -u ELECTRON_RUN_AS_NODE npm run typecheck`
Expected: clean. (Confirms the `navKey({ kind, id, path })` targets satisfy `NavTarget` and `c.sets ?? []` handles `SetNode`'s optional `sets`.)

- [ ] **Step 6: Commit**

```bash
git add src/renderer/src/Navigation/treeNavKeys.ts src/renderer/src/Navigation/treeNavKeys.test.ts
git commit -m "feat(thumbnails): existingNavKeys — the tree's complete thumbnail key set"
```

---

### Task 2: Existence-prune — union key set, gate to open, reconcile comments

Two behavioral changes plus comment reconciliation: **(a)** widen the eviction key set to `existingNavKeys(tree) ∪ recents ∪ pins` (the union is the fault guard — Finding 1); **(b)** gate the trigger to genuine nexus-open instead of every `load()` refetch (Finding 2). `applyTree` at `store.ts:673` populates the tree before the trigger fires, so `get().tree` is the new nexus's tree. Main's `evictThumbnails` is unchanged; the subsystem comments become true and get restated as durable truth.

**Files:**
- Modify: `src/renderer/src/store.ts` — `evictThumbs` (~`:1199`) and the trigger comment (~`:717`)
- Modify: `src/main/io/thumbnails.ts` — header comment (`:5`) and `evictThumbnails` doc (`:109-110`)
- Modify: `src/renderer/src/Navigation/useNavThumbnails.ts` — `dropCapturedOutside` doc (`:43-44`)

**Interfaces:**
- Consumes: `existingNavKeys` from `./Navigation/treeNavKeys` (Task 1).

- [ ] **Step 1: Add the import to `store.ts`**

Beside the existing `navKey` import from `./Navigation/navRecents`, add:

```ts
import { existingNavKeys } from './Navigation/treeNavKeys'
```

- [ ] **Step 2: Rewrite `evictThumbs` (store.ts ~:1199)**

```ts
    evictThumbs: () => {
      const tree = get().tree
      if (!tree) return
      // Existence ∪ recents ∪ pins: the tree is the live set, but its fs walk reads a subtree as empty
      // on a transient error — so recents/pins backstop a just-visited cover against a false-empty read.
      const live = [
        ...existingNavKeys(tree),
        ...get().recents.map(navKey),
        ...get().pins.map(navKey),
      ]
      dropCapturedOutside(new Set(live)) // markers drop only for entities in neither the tree nor recents
      void window.nexus.capture.evict(live)
    },
```

(Replaces the old `const live = [...recents.map(navKey), ...pins.map(navKey)]` body — the union is a *superset* of it, so `navKey` stays imported and genuinely used; `dropCapturedOutside` unchanged.)

- [ ] **Step 3: Gate the trigger to genuine nexus-open (store.ts: move `:717` into the once-per-nexus block)**

`get().evictThumbs()` sits unconditionally at `:717`, so it fires on every `load()` — every structural-mutation refetch (`:1625`). Delete it from `:717` and move it into the existing once-per-nexus block (`if (get().activeTabId === '') {` at ~`:722`) as its first statement:

```ts
            if (get().activeTabId === '') {
              // Existence-prune the thumbnail cache — once per nexus-open, NOT on every mutation refetch
              // (which also calls load()). Orphans of entities deleted mid-session wait for the next
              // open; harmless, since a lingering thumbnail just isn't shown.
              get().evictThumbs()
              // …existing previews-sidecar + tab-set seeding continues here…
```

The `activeTabId === ''` signal is the codebase's established once-per-nexus gate (the tab set and previews sidecar already ride it — a mutation refetch has a seeded `activeTabId`, so eviction is skipped).

- [ ] **Step 4: Restate the main-side comments (thumbnails.ts)**

Line `:5` (header, last sentence):

```
// changed since its last shot; existence eviction drops only orphaned thumbnails (entity gone from disk).
```

The `evictThumbnails` doc (`:109-110`):

```ts
/** Delete thumbnails whose key isn't in `liveKeys` — the caller passes every navKey that still exists,
 *  so this drops only orphans (a deleted entity's leftover), never a live cover. No-op when the folder
 *  doesn't exist yet. */
```

- [ ] **Step 5: Restate the `dropCapturedOutside` comment (useNavThumbnails.ts ~:43)**

```ts
/** Forget markers for entities no longer in the live set (their thumbnails are being evicted as
 *  orphans) — a marker outliving its file would block the re-shoot forever, leaving a permanent
 *  placeholder. */
```

- [ ] **Step 6: Typecheck + full test suite**

Run: `env -u ELECTRON_RUN_AS_NODE npm run typecheck && npx vitest run`
Expected: typecheck clean; all tests pass (existing `thumbnails.test.ts` still green — `evictThumbnails`'s contract is unchanged, only its caller's key set changed).

- [ ] **Step 7: Live smoke (isolated, against the real cache)**

Build and verify no regression + the cache persists:

```bash
env -u ELECTRON_RUN_AS_NODE npm run build
```

Then, against a real nexus (the isolated `~/Test` harness per `Handoff.md` Working Notes):
1. Open a nexus, visit a page P → confirm `.nexus/assets/<nexusId>/thumbnails/page-<P.id>.jpg` is written.
2. Switch to another nexus and back (fires `evictThumbs` on reopen).
3. Confirm `page-<P.id>.jpg` **still exists** and P's Preview cover renders — before this change a cover outside the recents∪pins window was deleted here.
4. Confirm no console error from `nav:evictThumbs`, and the thumbnails dir isn't wiped.
5. Create or rename a page (a structural mutation → `load()` refetch) and confirm the thumbnails dir is **not** pruned — eviction is now gated to open, not mutations.

Expected: the file survives the reopen; covers persist; a mid-session mutation triggers no eviction.

- [ ] **Step 8: Commit**

```bash
git add src/renderer/src/store.ts src/main/io/thumbnails.ts src/renderer/src/Navigation/useNavThumbnails.ts
git commit -m "fix(thumbnails): existence-prune at nexus-open — persistent covers, no recents-window eviction"
```

---

### Considered & Rejected

- **Bare existence set, no recents∪pins union (the first draft).** Rejected after review: `existingNavKeys(tree)` derives from a fault-tolerant fs walk that reads a subtree as *empty* on a transient error (`readNexus.ts:174`/`:222`), so a bare existence set would delete live covers on fs flakiness — worse than the deterministic recents-rolloff it replaces, and squarely on Pommora's synced-folder (iCloud) target. The union costs two lines and closes it.
- **`readNexus` surfaces a "degraded read" flag; `evictThumbs` no-ops on it.** The airtight fix for the transient-fault window — but it needs a new field through the `nexus:state` IPC contract and main-side error tracking, disproportionate surface for regenerable data. The union backstop is the cheaper 90% that leaves only a rare, self-healing residual.
- **Existence-prune in main at `prepareOpenedNexus` (`index.ts:552`).** Main owns fs and already walks entities to stamp ULIDs, so it could delete orphans directly. Rejected: main would have to re-derive `kind:id` keys, duplicating `navKey` — the two-writers defect class this subsystem already got burned by. Keeping key derivation in the renderer's one `navKey` source is the safer call; main stays a dumb `evictThumbnails(root, keys)`.
- **Stop evicting entirely (pure append-only).** Simplest, but orphaned thumbnails (deleted entities) accumulate forever in a *synced* folder. Existence-pruning is the cheap bound that keeps amend-only honest.

### Non-Goals / Prospects

- **Cross-session capture-gate skip.** The `captured` marker map in `useNavThumbnails.ts:40` is session-scoped (cleared on nexus switch), so the first visit to an entity each session re-shoots even when a valid file exists. Harmless (it overwrites), just a redundant capture. Persisting the gate across sessions is a separate optimization, out of scope for B-6.
- **Cover-mode covers** (`frontmatter.cover`) are user-attached assets, not thumbnails — never touched by eviction. Only Preview-mode covers (`CardsView.tsx:468` `thumbSrc`) and NavGallery covers share this store, and both are fixed by this plan.
- **Synced-folder growth is intended, not capped.** Existence-pruning keeps a cover for every *visited* entity that still exists — over months that trends toward one small JPEG (480px, q78 — tens of KB) per entity, vs the old ~100 (recents cap) + pins. That's the direct consequence of B-6's "the cache never disappears"; capping it would reintroduce vanishing covers. If sync weight ever bites, an LRU-by-`atime` cap *within* the existence set is the escape hatch (Prospect), not a change to this plan.
- **Residual transient-fault window (after the union guard).** A cover rolled off recents *and* whose subtree transiently fails to read *at* an open still gets evicted — then self-heals on the next visit (thumbnails regenerate). The union shrinks this to a rare, self-correcting window; the "degraded read" flag (Considered & Rejected) would close it entirely if it ever proves worth the contract surface.

### Self-Review

- **Spec coverage (B-6):** retire window-pruning → Task 2 Step 2 (union key set). Amend-only → already true, asserted in Global Constraints, no task needed. Existence-pruning at nexus-open → Task 1 (the set) + Task 2 Step 3 (gated to the genuine-open trigger). ✓
- **Placeholder scan:** every code step carries complete code; commands are exact. ✓
- **Type consistency:** `existingNavKeys(tree: NexusTree): string[]` produced in Task 1, consumed verbatim in Task 2. `navKey` targets match `NavTarget` members (`collection`/`set`/`page`/`context`). `c.sets ?? []` matches `SetNode.sets?` optional / `CollectionNode.sets` required. ✓
- **Review round 1 (build-breaking, folded):** the briefed lazy-load fear was disproven (`readNexus` is a fully eager recursive walk). Folded the fs-fault regression (recents∪pins union guard, Task 2 Step 2) and the every-mutation trigger (open-gating, Task 2 Step 3); acknowledged the synced-folder growth as intended per B-6 (Non-Goals). Re-grounded at `readNexus.ts:174`/`:222`, `store.ts:702-717`/`:722`/`:1625`. ✓
