# ViewPane Properties Flow — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Spec:** `.claude/Planning/7-2 - ViewPane Properties Flow — Decision Log.md` (ratified, two adversarial rounds folded). Decision tags (A-1…E-8) referenced below are its entries.

**Goal:** The ViewPane Properties pane becomes the full assign surface — assigned properties + an "All Properties" registry disclosure with promote/drag/reorder, a strip-and-cache Remove with reconciled restore, a pane-gated Delete, a DRY nested slide, a 350px cap with the shared scroll-edge fade, and inline rename.

**Architecture:** Main stays authoritative: the registry file grows to `{ order, defs }`, Remove/Restore run as single `SchemaTransaction`s, and the tree exposes the ordered registry so watcher pushes keep the pane live. The renderer extends the existing `PropertiesPane` in place: an inner `PaneSlider` nests inside the outer one so every push slides (one primitive, reused), a bespoke insertion-line drag (the bandDnd recipe) classifies drops by region, and native menus ride the established popCellMenu/contextMenu patterns.

**Tech Stack:** Electron 42 main-process fs + IPC · React 19 renderer · zod codecs · vanilla-extract tokens · Vitest (real-fs `mkdtemp` for main, jsdom + `pointerHarness` for renderer).

## Global Constraints

- **IPC never throws across the boundary** — every handler returns `{ ok: true, … } | { ok: false, error }`.
- **Main owns the filesystem**; the renderer touches it only through the preload bridge.
- **Registry writes MUST flow through `mutateRegistry`** (`io/propertiesRegistry.ts:38`) — a bare read-modify-write loses concurrent updates.
- **No expensive work "on every X"**: drag uses a frozen snapshot (dirty-on-scroll, re-measure once), never per-move `getBoundingClientRect` loops.
- **Motion from tokens only** (`design-system/tokens/motion.ts`); the pane's beat is `duration.base` (280ms) + `easing.standard` (E-8).
- **Colors as hex via tokens**; no `rgb()`.
- **TDD, one green commit per task**, explicit-path staging (never `git add -A` — Nathan's live tweaks to `ViewPane.tsx`/`columnWidths.ts` may be in the tree).
- **Verification gates:** `npm run typecheck` + `npx vitest run` from `React/`, unmasked exits (`> /tmp/out 2>&1; echo $?`).
- **Main-process changes need a full dev-process restart** (not ⌘R) to test live.
- Duplicate property NAMES are allowed on create AND rename (D-3); names must still be non-empty.
- Reserved ids (`isReservedPropertyId`, `shared/properties.ts:114`) never appear in either pane group (E-5).

## File Map

| File | Role |
|---|---|
| `React/src/main/io/propertiesRegistry.ts` | registry file grows to `{ order, defs }` + lenient legacy read (T1) |
| `React/src/main/crud/registryProperty.ts` | create appends to order; duplicate names allowed (T1) |
| `React/src/main/properties/schema.ts` | `validateName` uniqueness becomes opt-out (T1) |
| `React/src/main/readNexus.ts` + `React/src/shared/types.ts` | `NexusTree.registry` exposure (T1) |
| `React/src/main/crud/removeProperty.ts` (new) | Remove = strip + cache; Restore = reconcile + write-back (T2) |
| `React/src/main/crud/deleteProperty.ts` | purge `property_cache` blocks on Delete (T2) |
| `React/src/main/index.ts` + `React/src/preload/index.ts` | `schema:assign`, `registry:reorder`, `property:menu` IPC (T2, T7) |
| `React/src/renderer/src/design-system/components/Reveal.tsx` | optional `duration` prop (T3) |
| `React/src/renderer/src/Components/Detail/PaneSlider.tsx` (+css) | `maxHeight` clamp + scrolling slot (T4) |
| `React/src/renderer/src/design-system/scroll-edge-fade.css` (new) | the hoisted sidebar edge fade (T4) |
| `React/src/renderer/src/Components/Detail/PropertiesPane.tsx` | inner slider, All Properties section, header ⊕/⋮, row menus (T3, T5, T7) |
| `React/src/renderer/src/Components/Detail/paneDndModel.ts` + `paneDnd.tsx` (new) | two-region drag model + gesture provider (T6) |
| `React/src/shared/propertyMenu.ts` + `React/src/main/propertyMenu.ts` (new) | native menu model + popper (T7) |
| `React/src/renderer/src/store.ts` | `renamingProperty` channel (T7) |

---

### Task 1: Registry order + tree exposure + flat duplicate-name policy (main)

**Files:**
- Modify: `React/src/main/io/propertiesRegistry.ts` (whole file — shape change)
- Modify: `React/src/main/crud/registryProperty.ts:17-52` (order append, callers of the new shape)
- Modify: `React/src/main/properties/schema.ts:38-57` (`validateName` opt-out)
- Modify: `React/src/main/readNexus.ts:302,234,364-373` · `React/src/shared/types.ts:158-177`
- Modify: `React/src/main/crud/deleteProperty.ts:47,75-76` (new shape at its two registry touches)
- Test: `React/src/main/io/propertiesRegistry.test.ts`, `React/src/main/crud/registryProperty.test.ts`

**Interfaces:**
- Produces: `type RegistryFile = { order: string[]; defs: PropertyRegistry }`; `readRegistry(root): Promise<RegistryFile>`; `mutateRegistry<T>(root, fn: (reg: RegistryFile) => { next?: RegistryFile; result: T }): Promise<T>`; `reorderRegistry(root, propertyId, toIndex): Promise<Result<null>>` (exported from `registryProperty.ts`); `NexusTree.registry: PropertyDefinition[]` (ordered, reserved excluded by consumers not here).
- Consumes: existing `PropertyRegistry`, `group_order` codec precedent (`shared/views.ts:191-195`).

- [ ] **Step 1: Failing tests — the new shape + legacy migration + order ops**

Append to `React/src/main/io/propertiesRegistry.test.ts`:

```typescript
describe('RegistryFile shape — { order, defs } with legacy migration', () => {
  it('reads a legacy bare-Record file as { order: [], defs }', async () => {
    const root = await mkdtemp(join(tmpdir(), 'pom-reg-'))
    await mkdir(join(root, '.nexus'), { recursive: true })
    await writeFile(join(root, '.nexus/properties.json'), JSON.stringify({ prop_a: def('prop_a') }))
    const reg = await readRegistry(root)
    expect(reg.defs.prop_a?.id).toBe('prop_a')
    expect(reg.order).toEqual([])
  })

  it('round-trips { order, defs } and element-filters junk order entries', async () => {
    const root = await mkdtemp(join(tmpdir(), 'pom-reg-'))
    await mkdir(join(root, '.nexus'), { recursive: true })
    await writeFile(
      join(root, '.nexus/properties.json'),
      JSON.stringify({ order: ['prop_a', 42, null, 'prop_gone'], defs: { prop_a: def('prop_a') } })
    )
    const reg = await readRegistry(root)
    expect(reg.order).toEqual(['prop_a']) // non-strings AND ids without defs dropped
  })
})
```

Append to `React/src/main/crud/registryProperty.test.ts`:

```typescript
it('createProperty appends the new id to the nexus order (A-9)', async () => {
  const root = await freshRoot()
  await createProperty(root, def('prop_a'))
  await createProperty(root, def('prop_b'))
  expect((await readRegistry(root)).order).toEqual(['prop_a', 'prop_b'])
})

it('duplicate names are allowed on create AND rename — flat D-3 policy', async () => {
  const root = await freshRoot()
  await createProperty(root, { ...def('prop_a'), name: 'Status' })
  const dup = await createProperty(root, { ...def('prop_b'), name: 'Status' })
  expect(dup.ok).toBe(true)
  const ren = await editProperty(root, 'prop_a', { name: 'Status' }) // rename-into-collision
  expect(ren.ok).toBe(true)
})

it('a blank name still rejects', async () => {
  const root = await freshRoot()
  expect((await createProperty(root, { ...def('prop_a'), name: '  ' })).ok).toBe(false)
})

it('reorderRegistry moves an id within the order', async () => {
  const root = await freshRoot()
  for (const id of ['prop_a', 'prop_b', 'prop_c']) await createProperty(root, def(id))
  await reorderRegistry(root, 'prop_c', 0)
  expect((await readRegistry(root)).order).toEqual(['prop_c', 'prop_a', 'prop_b'])
})
```

(Reuse each file's existing `def()`/`freshRoot()`-style helpers; if the file builds roots inline, mirror its exact `mkdtemp` idiom.)

- [ ] **Step 2: Run to verify failure** — `cd React && npx vitest run src/main/io/propertiesRegistry.test.ts src/main/crud/registryProperty.test.ts` → FAIL (`reg.defs` undefined, `reorderRegistry` not exported).

- [ ] **Step 3: Implement the shape**

`propertiesRegistry.ts` — replace the type + IO (keep `mutateRegistry`'s chain exactly as-is, only the generic changes):

```typescript
export type PropertyRegistry = Record<string, PropertyDefinition>
/** The on-disk registry file: defs + the nexus-wide cosmetic order (B-1/B-2). */
export type RegistryFile = { order: string[]; defs: PropertyRegistry }

/** Lenient read: absent/corrupt → empty; a legacy bare-Record file reads as { order: [], defs };
 *  order is element-filtered (non-strings and ids without defs dropped — B-3). */
export async function readRegistry(root: string): Promise<RegistryFile> {
  const raw = await readJson(registryPath(root)) // keep the file's existing raw-read helper
  if (!isPlainObject(raw)) return { order: [], defs: {} }
  const isFileShape = isPlainObject(raw.defs) || Array.isArray(raw.order)
  const rawDefs = isFileShape ? (isPlainObject(raw.defs) ? raw.defs : {}) : raw
  const defs: PropertyRegistry = {}
  for (const [id, d] of Object.entries(rawDefs)) {
    const parsed = propertyDefinition.safeParse(d)
    if (parsed.success) defs[id] = parsed.data
  }
  const rawOrder = isFileShape && Array.isArray(raw.order) ? raw.order : []
  const order = rawOrder.filter((x): x is string => typeof x === 'string' && x in defs)
  return { order, defs }
}
```

`writeRegistry(root, registry: RegistryFile)` writes the object verbatim. `mutateRegistry<T>` keeps its chain, `fn` now receives/returns `RegistryFile`. Update the four call sites to `.defs[...]` access: `registryProperty.ts` (all three fns), `deleteProperty.ts:47` (fetch) and `:76` (remove — `delete next.defs[propertyId]` AND `next.order = next.order.filter((id) => id !== propertyId)`), `readNexus.ts:302` (pass `reg.defs` into `resolveAssignedSchema` — its own signature stays `PropertyRegistry`).

- [ ] **Step 4: Implement order-append + reorder + flat name policy**

`registryProperty.ts` — inside `createProperty`'s `mutateRegistry` fn, after inserting the def: `next.order = [...reg.order.filter((id) => id !== def.id), def.id]`. Add:

```typescript
/** Move propertyId to toIndex in the nexus-wide cosmetic order (C-1). Clamped; unknown id no-ops ok:false. */
export function reorderRegistry(root: string, propertyId: string, toIndex: number): Promise<Result<null>> {
  return mutateRegistry(root, (reg) => {
    if (!(propertyId in reg.defs)) return { result: fail('not-found', 'Unknown property.', 'schema') }
    const order = reg.order.filter((id) => id !== propertyId)
    order.splice(Math.max(0, Math.min(toIndex, order.length)), 0, propertyId)
    return { next: { ...reg, order }, result: ok(null) }
  })
}
```

`properties/schema.ts` — `validateName(name, existing, excludeId?, opts: { unique?: boolean } = {})`: keep the non-empty-after-trim check; wrap the case-insensitive clash (line 46) in `if (opts.unique !== false) { … }`. `validateDefinition(def, existing, opts?)` forwards `opts` to its `validateName` call (line 57). In `registryProperty.ts`: `createProperty` calls `validateDefinition(def, Object.values(reg.defs), { unique: false })`; `editProperty`'s rename branch calls `validateName(next.name, Object.values(reg.defs), propertyId, { unique: false })`. Agenda's callers pass nothing → uniqueness unchanged there.

- [ ] **Step 5: Expose the ordered registry on the tree (E-1)**

`shared/types.ts` (NexusTree, after `accent`): `/** Every registry definition, in the nexus-wide cosmetic order (order-listed first, unlisted appended). */ registry: PropertyDefinition[]`. In `readNexus.ts`, where `readRegistry` already loads (line 302 area), compute once and add to the return object (line ~373):

```typescript
const orderedRegistry = [
  ...reg.order.map((id) => reg.defs[id]),
  ...Object.values(reg.defs).filter((d) => !reg.order.includes(d.id))
].filter((d): d is PropertyDefinition => d !== undefined)
```

Fix the tree fixtures/tests that construct `NexusTree` literals (typecheck will list them — add `registry: []`).

- [ ] **Step 6: Green + typecheck** — `npx vitest run` + `npm run typecheck`, both exit 0. Expect the OLD duplicate-name-rejection test in `registryProperty.test.ts` to now fail — flip its assertion (that's the D-3 policy change, not collateral).

- [ ] **Step 7: Commit**

```bash
git add React/src/main/io/propertiesRegistry.ts React/src/main/io/propertiesRegistry.test.ts React/src/main/crud/registryProperty.ts React/src/main/crud/registryProperty.test.ts React/src/main/properties/schema.ts React/src/main/crud/deleteProperty.ts React/src/main/readNexus.ts React/src/shared/types.ts
git commit -m "feat(registry): {order,defs} file shape + nexus order ops + ordered tree.registry; duplicate names allowed on the registry paths (7-2 T1)"
```

(Also stage whatever fixture/test files typecheck forced — explicit paths only.)

---

### Task 2: Remove = strip + cache · Restore = reconcile + write-back · Delete purges (main)

**Files:**
- Create: `React/src/main/crud/removeProperty.ts` + `React/src/main/crud/removeProperty.test.ts`
- Modify: `React/src/main/crud/assignment.ts:21-27` (assign triggers restore), `React/src/main/crud/deleteProperty.ts:59-62` (cache purge)
- Modify: `React/src/main/index.ts:547-559` (`schema:delete` → the new remove), `+~501` (`schema:assign` handler), `+` (`registry:reorder` handler)
- Modify: `React/src/preload/index.ts:~88` (`schema.assign`, `registry.reorder`)
- Test: `React/src/main/crud/deleteProperty.test.ts` (purge case)

**Interfaces:**
- Produces: `removeProperty(root, collectionFolder, propertyId): Promise<Result<null>>`; `restoreCachedValues(root, collectionFolder, propertyId): Promise<Result<null>>` (called from `assignProperty`); sidecar block shape `property_cache: { [propId]: { removed_at: string; values: Record<pageId, unknown> } }` (C-6); preload `window.nexus.schema.assign(containerPath, propertyId)` and `window.nexus.registry.reorder(propertyId, toIndex)`.
- Consumes: T1's `RegistryFile`; `SchemaTransaction` (`io/schemaTransaction.ts` — `stage(target, content)` / `commit()`); `stripPageMember(content, propertyId): string | null` (`crud/schema.ts:45-52`); `parsePropertyValue`/`applyPropertyValue` (`shared/propertyValue.ts:54,145`).

- [ ] **Step 1: READ FIRST** — open `crud/deleteProperty.ts:24-77` in full and note (a) how it enumerates a collection folder's member `.md` files (lines 64-73) and (b) the snapshot's `values` collection. `removeProperty` reuses the same enumeration — extract it to a shared helper `collectMembers(folder): Promise<string[]>` in `deleteProperty.ts` (exported) rather than duplicating the walk.

- [ ] **Step 2: Failing tests** — `removeProperty.test.ts` (mirror `deleteProperty.test.ts`'s harness: `mkdtemp` + `createFolderEntity` + real pages):

```typescript
describe('removeProperty — strip + cache (C-3/C-6)', () => {
  it('strips the value from every member page, caches {pageId: raw}, and unassigns — one transaction', async () => {
    const { root, folder } = await collectionWith('prop_s', { 'A.md': { $status: 'active' }, 'B.md': { $status: 'done' } })
    const r = await removeProperty(root, folder, 'prop_s')
    expect(r.ok).toBe(true)
    expect(await pageProperties(folder, 'A.md')).toEqual({})            // frontmatter clean
    const sidecar = await readSidecarRaw(folder)
    expect(sidecar.properties).not.toContain('prop_s')                   // unassigned
    const block = (sidecar.property_cache as any).prop_s
    expect(Object.values(block.values)).toEqual([{ $status: 'active' }, { $status: 'done' }])
    expect(typeof block.removed_at).toBe('string')
  })

  it('is a no-op when the property is not assigned (E-6 — never overwrites a cache with emptiness)', async () => {
    const { root, folder } = await collectionWith('prop_s', { 'A.md': { $status: 'active' } })
    await removeProperty(root, folder, 'prop_s')
    const before = (await readSidecarRaw(folder)).property_cache
    const again = await removeProperty(root, folder, 'prop_s')
    expect(again.ok).toBe(true)
    expect((await readSidecarRaw(folder)).property_cache).toEqual(before)
  })
})

describe('restore on re-assign — per-value schema-currency reconciliation (MAJOR-2 fold)', () => {
  it('restores cached values to pages still present and clears the block', async () => {
    const { root, folder } = await collectionWith('prop_s', { 'A.md': { $status: 'active' } })
    await removeProperty(root, folder, 'prop_s')
    await assignProperty(folder, 'prop_s') // assign triggers restore (root derivable from folder? see Step 4)
    expect(await pageProperties(folder, 'A.md')).toEqual({ prop_s: { $status: 'active' } })
    expect((await readSidecarRaw(folder)).property_cache?.prop_s).toBeUndefined()
  })

  it('drops a value whose option no longer exists; keeps conforming siblings', async () => { /* remove → delete the 'active' option from the def via editProperty → re-assign → A.md restores nothing, B.md ('done') restores */ })

  it('drops a value whose def type changed since caching', async () => { /* remove → editProperty type→number → re-assign → nothing restored, block cleared */ })

  it('a page deleted while cached is skipped (entry dropped, no error)', async () => { /* remove → rm page → re-assign → ok:true */ })
})
```

Fill the three sketched bodies with the same helpers as the first — each is remove → mutate def/fs → `assignProperty` → assert `pageProperties` + block cleared. Add to `deleteProperty.test.ts`:

```typescript
it('global Delete purges the property_cache block in every assigner sidecar (D-6)', async () => {
  const { root, folder } = await collectionWith('prop_s', { 'A.md': { $status: 'active' } })
  await removeProperty(root, folder, 'prop_s')
  await deleteProperty(root, 'prop_s')
  expect((await readSidecarRaw(folder)).property_cache?.prop_s).toBeUndefined()
})
```

**Note:** after Remove, the collection is no longer an assigner — `deleteProperty`'s purge must therefore sweep cache blocks by scanning ALL collection sidecars (the same walk `assigners` does over the tree, but testing `property_cache` keys), not just current assigners.

- [ ] **Step 3: Run to verify failure** — module not found / assertions fail.

- [ ] **Step 4: Implement `removeProperty.ts`**

```typescript
/** Remove (C-3): strip propertyId's value from every member page, cache {pageId: raw} on the
 *  collection sidecar, and unassign — ONE SchemaTransaction (E-3), so no partial state survives
 *  a failure. Not assigned → no-op ok (E-6). */
export async function removeProperty(root: string, collectionFolder: string, propertyId: string): Promise<Result<null>> {
  const sidecarRead = await readCollectionSidecar(collectionFolder) // the assignment.ts read helper — hoist/export it
  if (!sidecarRead || !sidecarRead.ids.includes(propertyId)) return ok(null)
  const tx = new SchemaTransaction()
  const values: Record<string, unknown> = {}
  for (const file of await collectMembers(collectionFolder)) {
    const content = await readFile(file, 'utf8')
    const raw = readFrontmatterFields(content).properties?.[propertyId] // the mutate.ts frontmatter reader
    const pageId = readFrontmatterFields(content).id
    if (raw === undefined || typeof pageId !== 'string') continue
    values[pageId] = raw
    const stripped = stripPageMember(content, propertyId)
    if (stripped !== null) tx.stage(file, stripped)
  }
  const cache = { ...(sidecarRead.sidecar.property_cache as Record<string, unknown> | undefined) }
  cache[propertyId] = { removed_at: new Date().toISOString(), values }
  tx.stage(
    sidecarPath(collectionFolder),
    serializeSidecar({ ...sidecarRead.sidecar, properties: sidecarRead.ids.filter((id) => id !== propertyId), property_cache: cache })
  )
  await tx.commit()
  return ok(null)
}
```

(Use the file's real helper names — `readCollectionSidecar`/`sidecarPath`/`serializeSidecar` stand for whatever `assignment.ts:12-19` + `writeSidecar` actually compose; hoist, don't duplicate. The sidecar is `z.looseObject`, so `property_cache` rides as a foreign key — verified.)

`restoreCachedValues` (same file): read sidecar block → if none, `ok(null)`; else fetch the def from `readRegistry(root)` and for each `[pageId, raw]`: resolve the page file among `collectMembers` (match frontmatter `id`), skip missing pages, run the reconcile gate, and stage `mergeFrontmatter` writes (the `setProperty` pattern, `main/mutate.ts:343-362`) applying `applyPropertyValue(fields.properties, propertyId, parsed)`; stage the sidecar with the block deleted; ONE `tx.commit()`. The reconcile gate (pure, exported for tests):

```typescript
const KIND_FOR_TYPE: Record<string, PropertyValue['kind'][]> = {
  number: ['number'], checkbox: ['checkbox'], datetime: ['datetime'], url: ['url'],
  select: ['select'], status: ['status'], multi_select: ['multiSelect'], context: ['context'], file: ['file']
}
/** Per-value schema-currency gate (round-2 fold): kind must match the def's CURRENT type, and
 *  select/status values must be live options (multiSelect intersects; empty intersection drops). */
export function reconcileCachedValue(def: PropertyDefinition, raw: unknown): PropertyValue | null {
  let parsed: PropertyValue
  try { parsed = parsePropertyValue(raw) } catch { return null }
  if (parsed.kind === 'null' || !(KIND_FOR_TYPE[def.type] ?? []).includes(parsed.kind)) return null
  const options = def.type === 'status'
    ? (def.status_groups ?? []).flatMap((g) => g.options.map((o) => o.value))
    : (def.select_options ?? []).map((o) => o.value)
  if (parsed.kind === 'select' || parsed.kind === 'status') return options.includes(parsed.value) ? parsed : null
  if (parsed.kind === 'multiSelect') {
    const kept = parsed.value.filter((v) => options.includes(v))
    return kept.length ? { kind: 'multiSelect', value: kept } : null
  }
  return parsed
}
```

Wire the trigger: `assignProperty` (`assignment.ts:21-27`) gains a `root` parameter — `assignProperty(root, collectionFolder, propertyId)` — appends the id (existing behavior), then `await restoreCachedValues(root, collectionFolder, propertyId)`. Update its call sites (the `schema:add` handler assigns post-create; tests).

`deleteProperty.ts`: in the sidecar-staging loop (lines 59-62) delete `sidecar.property_cache?.[propertyId]` before staging; and extend the fan-out list to every collection sidecar holding a `property_cache[propertyId]` block even if unassigned (walk the same folders `assigners` walks; stage those sidecars too).

- [ ] **Step 5: IPC + preload**

`main/index.ts`: repoint `schema:delete` (lines 547-559) from `unassignProperty` to `removeProperty(root, folder, propertyId)` — same channel, same envelope (MINOR-2's reconciliation: the word *Delete* now lives only in `property:delete`). Add:

```typescript
ipcMain.handle('schema:assign', async (_e, containerPath: unknown, propertyId: unknown) => { /* resolveSchemaFolder like schema:delete; call assignProperty(root, folder, id); envelope */ })
ipcMain.handle('registry:reorder', async (_e, propertyId: unknown, toIndex: unknown) => { /* sessionRoot guard; reorderRegistry; envelope */ })
```

Mirror both in `preload/index.ts` under `schema.assign` / a new `registry: { reorder }` cluster, typed like the existing `schema.*` entries. Also declare them on the renderer's `window.nexus` type (wherever `schema` is typed — follow `schema.delete`'s declaration).

- [ ] **Step 6: Green + typecheck**, then **Commit**

```bash
git add React/src/main/crud/removeProperty.ts React/src/main/crud/removeProperty.test.ts React/src/main/crud/assignment.ts React/src/main/crud/assignment.test.ts React/src/main/crud/deleteProperty.ts React/src/main/crud/deleteProperty.test.ts React/src/main/index.ts React/src/preload/index.ts
git commit -m "feat(properties): Remove strips + caches restorably; re-assign reconciles per-value; Delete purges caches; assign + registry-order IPC (7-2 T2)"
```

---

### Task 3: The DRY nested slide (every push animates) + Reveal duration prop

**Files:**
- Modify: `React/src/renderer/src/design-system/components/Reveal.tsx:6-9,26` (add `duration?: string`)
- Modify: `React/src/renderer/src/Components/Detail/PropertiesPane.tsx` (subviews ride an inner `PaneSlider`)
- Test: `React/src/renderer/src/Components/Detail/propertiesPane.test.tsx` (new, jsdom)

**Interfaces:**
- Produces: `Reveal({ open, fill?, duration?, children })` — `duration` defaults to `duration.disclosure`, the pane passes `duration.base` (E-8). PropertiesPane's list↔detail becomes `<PaneSlider active={view.kind === 'list' ? 'a' : 'b'} …>` nested inside ViewPane's outer slider (A-7: one primitive per push — nesting composes; the inner resize retargets the outer viewport through its ResizeObserver natively).
- Consumes: `PaneSlider` as-is (T4 adds maxHeight).

- [ ] **Step 1: Failing test** — new `propertiesPane.test.tsx` with the cellGestures jsdom idiom (`createRoot`, `window.nexus` stub with `schema` spies, `IS_REACT_ACT_ENVIRONMENT`, `ResizeObserver` stub):

```typescript
it('list → editor renders BOTH slots (inner PaneSlider keeps them mounted) with the editor active', async () => {
  await mountPane() // PropertiesPane with a 2-def schema stub
  await act(async () => { chevronRowFor('Status').click() })
  const slots = host.querySelectorAll('[inert]')
  expect(slots.length).toBe(1)                      // exactly one inert slot = slider semantics
  expect(host.textContent).toContain('Status')      // editor header
  expect(host.textContent).toContain('New Property')// list still mounted beneath
})
```

- [ ] **Step 2: Run — FAIL** (today the subviews are early-return swaps; the list unmounts).

- [ ] **Step 3: Implement** — `Reveal` gains `duration?: string` (thread into the `outer` style's transition; default unchanged). `PropertiesPane` restructures: keep the `SubView` state machine, but return ONE tree:

```tsx
const list = ( /* the current list JSX incl. header + rows */ )
const detail = view.kind === 'type' ? ( /* type picker JSX */ ) : view.kind === 'edit' ? ( /* editor JSX */ ) : null
return <PaneSlider active={view.kind === 'list' ? 'a' : 'b'} slotA={list} slotB={detail ?? <span />} minWidth={245} minHeight={245} />
```

The back rows keep their existing handlers (`backToList`). ViewPane's outer slider is untouched — pushing Properties slides the outer; pushing editor/type slides the inner; both ride `duration.base` (paneSlider.css) so every swap animates (A-7) with zero per-window wiring.

- [ ] **Step 4: Green + typecheck.** Also eyeball live (renderer HMR): root → Properties → editor → back all slide.

- [ ] **Step 5: Commit** — `git add` the three files + test; `git commit -m "feat(viewpane): every pane push slides — PropertiesPane subviews ride a nested PaneSlider; Reveal gains a duration override (7-2 T3)"`

---

### Task 4: 350px cap + scrolling slot + the hoisted scroll-edge fade

**Files:**
- Modify: `React/src/renderer/src/Components/Detail/PaneSlider.tsx:11-67` + `paneSlider.css.ts`
- Create: `React/src/renderer/src/design-system/scroll-edge-fade.css`
- Modify: `React/src/renderer/src/Sidebar/Sidebar.css:40-50` (consume the shared class) + the sidebar element's className (`Sidebar.tsx` nav element)
- Modify: `React/src/renderer/src/Components/Detail/ViewPane.tsx:103` (pass `maxHeight={350}`) — **this commit also carries Nathan's uncommitted 245 floors (D-4)**

**Interfaces:**
- Produces: `PaneSlider({ …, maxHeight?: number })` — the viewport height style becomes `Math.min(measured, maxHeight)`; each `.slot` gets `overflow-y: auto` + the `scroll-edge-fade` class when capped. The shared CSS class:

```css
/* design-system/scroll-edge-fade.css — the sidebar's Apple scroll-edge fade, hoisted (A-6).
   One knob: --edge-fade. Content scrolls under the static viewport mask. */
.scroll-edge-fade {
  --edge-fade: 22px;
  mask-image: linear-gradient(to bottom, transparent 0, #000 var(--edge-fade), #000 calc(100% - var(--edge-fade)), transparent 100%);
}
```

- [ ] **Step 1:** Write the class file; import it once beside the app's global css imports (follow how `toolbar.css` is imported). Replace Sidebar.css's inline mask block (lines 43-50) with nothing and add `scroll-edge-fade` to the sidebar scroll element's className — keep its local `--edge-fade` only if it must differ (it doesn't; delete).
- [ ] **Step 2:** `PaneSlider`: `maxHeight?: number` prop; `const clampedHeight = maxHeight ? Math.min(height, maxHeight) : height` used in the viewport style; on the slot wrappers add `style={{ maxHeight }}` + `overflowY: 'auto'` via a new `slotScrollable` class (gated on `maxHeight` presence) composed with `scroll-edge-fade`. **Gotcha:** the ResizeObserver measures the slot's natural (uncapped) height — measure an inner content div, not the scroll-capped slot box, or the clamp feeds back into the measurement. Restructure: `.slot > .slotContent` (measured) with the scroll+mask on `.slot`.
- [ ] **Step 3:** Verify live: a long list caps at 350, scrolls inside, edges fade top/bottom, the open animation still lands on one beat. jsdom test (same harness as T3): with 30 stub defs, the slot element carries the `scroll-edge-fade` class and `maxHeight: 350px` style.
- [ ] **Step 4: Commit** (includes `ViewPane.tsx` — Nathan's 245s + the new `maxHeight={350}`):

```bash
git add React/src/renderer/src/Components/Detail/PaneSlider.tsx React/src/renderer/src/Components/Detail/paneSlider.css.ts React/src/renderer/src/design-system/scroll-edge-fade.css React/src/renderer/src/Sidebar/Sidebar.css React/src/renderer/src/Sidebar/Sidebar.tsx React/src/renderer/src/Components/Detail/ViewPane.tsx React/src/renderer/src/Components/Detail/propertiesPane.test.tsx
git commit -m "feat(viewpane): 350px cap + scrolling slot; sidebar scroll-edge fade hoisted to one shared recipe; ViewPane 245 floors committed (7-2 T4)"
```

---

### Task 5: The All Properties section + header ⊕ create

**Files:**
- Modify: `React/src/renderer/src/design-system/symbols/index.tsx:51-90` (import `CirclePlus`, add `'circle-plus': CirclePlus`)
- Modify: `React/src/renderer/src/Components/Detail/PropertiesPane.tsx` (list view gains the section; footer create-row + its separator REMOVED; header gains ⊕)
- Test: extend `propertiesPane.test.tsx`

**Interfaces:**
- Consumes: `useSession((s) => s.tree)?.registry` (T1), `window.nexus.schema.assign` (T2), `Reveal` duration prop (T3).
- Produces: the list layout Task 6 hangs regions on: assigned rows render in a `div[data-group="assigned"]` wrapper, registry rows in `div[data-group="all"]` — paneDnd's region rects (E-4).

- [ ] **Step 1: Failing tests**

```typescript
it('All Properties lists only unassigned, unreserved registry defs, in nexus order (A-4/E-5/B-1)', async () => {
  await mountPane({ registry: [def('prop_x', 'Effort'), def('prop_s', 'Status'), def('_title', 'Title')], schema: [def('prop_s', 'Status')] })
  await act(async () => { disclosureRow().click() })
  const all = host.querySelector('[data-group="all"]')!
  expect(all.textContent).toContain('Effort')
  expect(all.textContent).not.toContain('Status')  // assigned — never in both groups
  expect(all.textContent).not.toContain('Title')   // reserved
})

it('+ assigns and the row promotes (IPC spy)', async () => {
  await mountPane({ registry: [def('prop_x', 'Effort')], schema: [] })
  await act(async () => { disclosureRow().click() })
  await act(async () => { plusFor('Effort').click() })
  expect(assignSpy).toHaveBeenCalledWith('Col', 'prop_x')
})

it('header ⊕ opens the type picker; the footer create-row is gone (A-9)', async () => {
  await mountPane()
  expect(host.textContent).not.toContain('New Property')
  await act(async () => { headerPlus().click() })
  expect(host.textContent).toContain('Checkbox') // a CREATABLE_TYPES row
})
```

- [ ] **Step 2: FAIL**, then **Step 3: Implement**

List view structure (replacing the current list return):

```tsx
<>
  <div className={s.paneHeader}>{/* new viewPane.css class: flex row */}
    <MenuBackRow label="Properties" onClick={onBack} />
    <button type="button" className={s.headerAction} aria-label="New Property" onClick={() => setView({ kind: 'type' })}>
      <Icon name="circle-plus" size={16} />
    </button>
  </div>
  <MenuSeparator flush />
  <div data-group="assigned">{props.map((d) => ( /* existing MenuItem row, unchanged */ ))}</div>
  <MenuItem className={s.allHeading} leading={<ChevronRight size={12} className={cx(s.twisty, allOpen && s.twistyOpen)} />} onClick={() => setAllOpen((o) => !o)}>
    All Properties
  </MenuItem>
  <Reveal open={allOpen} duration={duration.base}>
    <div data-group="all">
      {unassigned.map((d) => (
        <MenuItem key={d.id} className={s.allRow} leading={<PropertyTypeIcon type={d.type} />} trailing={
          <button type="button" className={s.rowPlus} aria-label={`Assign ${d.name}`} onClick={(e) => { e.stopPropagation(); void assign(d.id) }}>
            <Icon name="plus" size={12} />{/* 'plus' exists in the registry? verify — else lucide Plus like the old footer */}
          </button>
        }>{d.name}</MenuItem>
      ))}
    </div>
  </Reveal>
</>
```

With: `const registry = useSession((st) => st.tree?.registry) ?? []`; `const assignedIds = new Set(schema.map((d) => d.id))`; `const unassigned = registry.filter((d) => !assignedIds.has(d.id) && !isReservedPropertyId(d.id))`; `const assign = async (id: string) => { if ((await window.nexus.schema.assign(collectionPath, id)).ok) await load() }`. New `viewPane.css.ts` classes: `paneHeader` (flex, space-between, align center), `headerAction` (the iconButton recipe at 20×20, label-secondary), `allHeading` (footnote.emphasized + `label-tertiary` color var + the left-chevron `twisty` rotate on `--disclosure` — mirror Sidebar's `.twisty` transform), `allRow` (label-tertiary tone on `titleText` via a color override), `rowPlus` (bare 16×16 icon button, secondary). `allOpen` = `useState(false)` (default-closed; flip the literal if Nathan wants it open).

- [ ] **Step 4: Green + typecheck + live look** (disclosure unfolds WITH the pane resize on one beat — the T3/T4 plumbing makes this automatic). **Step 5: Commit** — `git add` symbols/index.tsx, PropertiesPane.tsx, viewPane.css.ts, the test; `"feat(viewpane): All Properties disclosure + promote + circle-plus header create; footer create-row removed (7-2 T5)"`

---

### Task 6: The two-region pane drag

**Files:**
- Create: `React/src/renderer/src/Components/Detail/paneDndModel.ts` + `.test.ts` (pure), `React/src/renderer/src/Components/Detail/paneDnd.tsx`
- Modify: `PropertiesPane.tsx` (wrap the two groups in the provider; rows register), `viewPane.css.ts` (drop-line + `allHighlight` classes)
- Test: extend `propertiesPane.test.tsx` (gesture cases via `pointerHarness`)

**Interfaces:**
- Produces (model — mirror `bandDndModel`'s style):

```typescript
export type PaneRow = { id: string; group: 'assigned' | 'all' }
export type PaneDrop =
  | { kind: 'reorder-assigned'; propId: string; toIndex: number }   // → schema.reorder
  | { kind: 'reorder-nexus'; propId: string; toIndex: number }      // → registry.reorder
  | { kind: 'assign'; propId: string; toIndex: number }             // all → assigned slot (C-2)
  | { kind: 'unassign'; propId: string }                            // assigned → all (C-3; no index — natural-slot snap, C-4)
export type PaneSlot = { drop: PaneDrop; lineY: number | null; highlightAll: boolean }
export function paneSlot(rows: MeasuredRow[], byId: Map<string, PaneRow>, regions: { assigned: { top: number; bottom: number }; all: { top: number; bottom: number } }, pointerY: number, draggedId: string): PaneSlot | null
```

Classification (E-4, region-owned): the pointer's region decides everything. Dragged-from-assigned + pointer in assigned → `reorder-assigned` at the nearest slot; dragged-from-assigned + pointer in the all region → `unassign` with `highlightAll: true`, `lineY: null` (the AREA highlights, no insertion line — the row lands at its nexus slot, C-4). Dragged-from-all + pointer in all → `reorder-nexus`; dragged-from-all + pointer in assigned → `assign` at the slot with an insertion line. Outside both regions → null (release = no-op).

- Consumes: `ACTIVATION`, `DROP_LINE_INSET`, `suppressNextClick` (`design-system/interactions/shared.ts`); the bandDnd gesture skeleton (`Table/bandDnd.tsx` — copy its listener/snapshot/ghost structure, swap the model); `startAutoScroll`-style edge scrolling from `design-system/interactions/autoscroll.ts` for the capped slot; commits via `window.nexus.schema.reorder/assign` + `window.nexus.registry.reorder` + `removeProperty` through `schema.delete`.

- [ ] **Step 1: Failing model tests** (`paneDndModel.test.ts`, pure — rows at synthetic Y coords):

```typescript
const rows = [r('a1', 10, 30), r('a2', 30, 50), r('x1', 70, 90), r('x2', 90, 110)] // a*=assigned, x*=all
const regions = { assigned: { top: 10, bottom: 50 }, all: { top: 70, bottom: 110 } }

it('assigned→assigned reorders at the slot', () => expect(slot(25, 'a2')!.drop).toEqual({ kind: 'reorder-assigned', propId: 'a2', toIndex: 0 }))
it('assigned→all is unassign with the area highlight and NO line (C-4)', () => {
  const s = slot(80, 'a1')!
  expect(s.drop).toEqual({ kind: 'unassign', propId: 'a1' })
  expect(s.highlightAll).toBe(true); expect(s.lineY).toBeNull()
})
it('all→assigned assigns at the slot with a line (C-2)', () => {
  const s = slot(30, 'x1')!
  expect(s.drop).toEqual({ kind: 'assign', propId: 'x1', toIndex: 1 }); expect(s.lineY).not.toBeNull()
})
it('all→all reorders the nexus order (C-1)', () => expect(slot(105, 'x1')!.drop).toEqual({ kind: 'reorder-nexus', propId: 'x1', toIndex: 1 }))
it('outside both regions → null', () => expect(slot(200, 'a1')).toBeNull())
```

- [ ] **Step 2: FAIL → implement the model** (slot math: nearest row-boundary within the region, index = boundaries above the pointer among that group's rows minus the dragged row when same-group — the `bandDndModel` before/after arithmetic, one region at a time).

- [ ] **Step 3: The provider** — copy `bandDnd.tsx`'s skeleton verbatim and adapt: `PaneDnd({ rows: PaneRow[], onDrop: (drop: PaneDrop) => void, children })`, `usePaneDrag(id)` → `{ ref, handle, isDragging }` with the WHOLE row as the drag surface (`handle` spread on the MenuItem wrapper; `begin` ignores pointerdowns on `button`/`input` targets so ⊕/chevron/rename stay clean). Keep: frozen snapshot + `markSnapshotDirty` on capture-phase scroll (E-4), the portal ghost + insertion line (reuse the `table-drop-line` styling as new viewPane classes), `suppressNextClick()` on committed drops, and Esc-abort — registered `window.addEventListener('keydown', onKey, { capture: true })` with `e.stopImmediatePropagation()` while a drag is active, so the Toolbar's `useDismiss` Escape never closes the dropdown mid-drag (grounded: dismissal is pointerdown-outside + Escape only — a release outside can't dismiss by construction). Region rects measured from the two `[data-group]` wrappers into the snapshot. While the slot is `highlightAll`, add the `allHighlight` class (a `state.hover`-tone background) to the all-group wrapper.
- [ ] **Step 4: Wire commits in PropertiesPane** — `onDrop` routes: `reorder-assigned` → `schema.reorder(collectionPath, propId, toIndex)`; `reorder-nexus` → `registry.reorder(propId, toIndex)`; `assign` → `schema.assign(collectionPath, propId)` then `schema.reorder(collectionPath, propId, toIndex)` (assign appends; the reorder places it); `unassign` → `schema.delete(collectionPath, propId)` (the Remove). Each followed by `await load()`.
- [ ] **Step 5: jsdom gesture test** (pointerHarness: `stubRect` rows + regions, firePointer down/move/up): one assigned→all drag asserts the `schema.delete` spy; one all→assigned asserts assign+reorder order. **Step 6: green + typecheck + live feel check.** **Step 7: Commit** — the five files; `"feat(viewpane): two-region property drag — reorder/assign/unassign with area-highlight snap (7-2 T6)"`

---

### Task 7: Native menus (⋮ Remove/Delete · row Rename/Remove) + the inline-rename channel

**Files:**
- Create: `React/src/shared/propertyMenu.ts`, `React/src/main/propertyMenu.ts`
- Modify: `React/src/main/index.ts` (the `property:menu` handler + Delete's confirm), `React/src/preload/index.ts` (`propertyMenu` + typing)
- Modify: `React/src/renderer/src/store.ts:371-376` region (the parallel channel), `PropertiesPane.tsx` (⋮ header, row `onContextMenu`, inline-rename row state; the editor's footer Delete row REMOVED)
- Test: `React/src/shared/propertyMenu.test.ts` (model), extend `propertiesPane.test.tsx`

**Interfaces:**
- Produces:

```typescript
// shared/propertyMenu.ts — the pure model (the cellMenuModel pattern)
export type PropertyMenuContext =
  | { kind: 'editor'; name: string }        // ⋮ → Remove · Delete (A-8; Delete pane-gated + confirm)
  | { kind: 'assigned-row'; name: string }  // right-click → Rename · Remove (A-10)
  | { kind: 'registry-row'; name: string }  // right-click → Rename only
export type PropertyMenuAction = 'property:rename' | 'property:remove' | 'property:destroy'
export function propertyMenuModel(ctx: PropertyMenuContext): Array<{ label: string; action: PropertyMenuAction; destructive?: boolean }>
```

`main/propertyMenu.ts` pops it natively (the `popCellMenu` promise pattern); for `property:destroy` main FIRST runs the confirm dialog (the `contextMenu.ts:62-78` `dialog.showMessageBox` recipe — buttons `['Delete', 'Cancel']`, message `` `Delete “${name}” everywhere?` ``, detail "It is removed from every collection; a recovery snapshot lands in the nexus's .trash folder.") and resolves the action only on confirm. Preload: `propertyMenu: (ctx: PropertyMenuContext) => Promise<PropertyMenuAction | null>`.
- Store channel (net-new — MAJOR-1; RenamableTitle stays untouched): `renamingProperty: { collectionPath: string; propertyId: string } | null`, `beginPropertyRename(target)`, `cancelPropertyRename()`, `submitPropertyRename(newName)` → `window.nexus.schema.rename(collectionPath, propertyId, newName)` then `load()`, clearing the slot first (mirror `submitRename`'s eager-exit at `store.ts:374`).

- [ ] **Step 1: Failing model test** — `propertyMenuModel({kind:'editor'})` yields Remove then Delete(destructive); `assigned-row` yields Rename+Remove; `registry-row` yields Rename only.
- [ ] **Step 2: Implement model + main popper + preload** (envelope-free — it resolves an action or null, like `cellMenu`).
- [ ] **Step 3: Renderer wiring** — Editor header becomes a row: `MenuBackRow` + a right-aligned ⋮ button (`Icon name="ellipsis-vertical" size={16}`, the T5 `headerAction` class) whose click awaits `window.nexus.propertyMenu({ kind: 'editor', name: def.name })`: `property:remove` → `schema.delete` + `backToList()` + `load()`; `property:destroy` → `window.nexus.property.delete(def.id)` + `backToList()` + `load()`. Delete the footer `deleteRow` block (`PropertiesPane.tsx:97-102`). Rows: `onContextMenu` on assigned rows (`assigned-row` ctx: rename → `beginPropertyRename({collectionPath, propertyId: d.id})`; remove → `schema.delete`) and registry rows (`registry-row`). The row title renders an `EditableInput` (the `RenamableTitle` UX pattern, property-keyed) when `renamingProperty?.propertyId === d.id`, committing via `submitPropertyRename`.
- [ ] **Step 4: jsdom tests** — spy `window.nexus.propertyMenu` returning each action; assert the right IPC fires (`schema.delete` / `property.delete` spies) and that rename flips the row to an input whose Enter commits `schema.rename`. Confirm the footer Delete row is gone.
- [ ] **Step 5: Green + typecheck.** **Step 6: Commit** — `"feat(viewpane): property native menus (⋮ Remove/pane-gated Delete, row Rename/Remove) + the property inline-rename channel (7-2 T7)"`

---

### Task 8: Docs reconciliation + live visual pass + closeout

**Files:** `.claude/Features/Properties.md`, `.claude/History.md`, `.claude/Planning/6-28 - Table Views Part 3 — View Settings.md`, `.claude/Handoff.md`

- [ ] **Step 1: Restate the record (D-4/C-3 supersessions — REPLACE, never annotate):**
  - `Properties.md` §Schema Mutations: the **Unassign** row becomes *"Remove — strips the value from every member page and caches it (with which pages held it) on the Collection's sidecar; re-assigning restores every value that still conforms to the definition's current type + options."* §Validation: the unique-name sentence becomes the known quirk: *"Names need not be unique — definitions are ID-keyed, so twin names are mechanically safe (a deliberate quirk; the visible All Properties list makes accidental twins unlikely)."* §Where Properties Live: fold the pane's new shape (All Properties, nexus order, pane-gated Delete).
  - `History.md`: append a dated 7-2 entry recording the Remove reversal (with the V1→V2→7-2 provenance), the nexus order, duplicate-name policy, and the pane ship; do NOT edit the 07-01 entry beyond a pointer.
  - `6-28` spec: §Built gains the shipped pane items; §Pending drops what 7-2 delivered (drag-reorder, Remove/Delete surfacing).
  - `Handoff.md`: session block + Next Session updated.
- [ ] **Step 2: Full gates** — `npm run typecheck` + `npx vitest run` (unmasked exits), full suite green.
- [ ] **Step 3: Live CDP visual pass** (dev restart REQUIRED — main-process IPC changed): screenshots (Read, don't send — Nathan's on mobile): the pane at cap with fades, the disclosure unfold beat, a promote, a drag-out highlight, the ⋮ menu can't be screenshotted (native) — jsdom covers it. **Real-Nexus caution:** do drag/remove verification on a THROWAWAY property created for the test, then Delete it.
- [ ] **Step 4: Dispatch `code-simplifier` on the working-tree diff** (required before calling the arc complete), fold, re-run gates.
- [ ] **Step 5: Commit docs** (explicit paths) — `"docs(properties): 7-2 pane shipped — Remove/cache model, nexus order, duplicate-name quirk restated across the record"` — then the post-green `build-breaking-agent` pass per the Review Discipline before closeout.
