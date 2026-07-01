# PropertiesV2 — Data Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status: V3 — review rounds 1–2 folded, RATIFIED.** Round 1 = compile-grounding + logic/green-per-task agents. Round 2 = a focused verify of the restructure (came back clean but for `build.test.ts`, folded below). The load-bearing round-1 correction: **`PropertiesPane.tsx` is a LIVE, mounted property editor** (`ViewPane.tsx:93`, reachable via `SettingsDropdown`) that calls `window.nexus.schema.add/rename/delete`. So V1's "remove the `schema:*` surface" was wrong — V2 **keeps `schema:*` and repoints its implementation to the registry+assignment model**, leaving the renderer untouched. Other folds: the flip is one atomic task (the sidecar-semantics change can't coexist with the old CRUD); fixture split made explicit (`columns.test.ts:21` reads defs from the fixture); `updatePageProperty` (not `setPropertyValue`); `@shared/result` (not `../result`); `export { stripPageMember }`; `index/build.ts:148` confirmed as the SQLite consumer.

**Goal:** Flatten property *definitions* from per-Collection sidecars to one nexus-wide registry (`.nexus/properties.json`); each Collection's sidecar holds a flat `string[]` of the registry prop-ids it validates; `readNexus` joins ids→defs so a Collection's resolved schema is unchanged in shape for the renderer, and the live `schema:*` write surface is re-backed by registry + assignment ops with zero renderer changes.

**Architecture:** Main stays authoritative; the read path stays a single fs walk. `readNexus` loads the registry once and joins each Collection's assignment array into `CollectionNode.properties` (same `PropertyDefinition[]` the renderer already consumes — untouched). Writes split into **registry ops** (create/edit/delete a def) and **assignment ops** (assign/unassign/reorder on a Collection's `string[]`). The existing `schema:*` IPC handlers become thin V2 adapters (`add` = create+assign, `rename` = edit, `delete` = unassign, `reorder` = reorder-assignment, `changeType` = edit-type). Delete fans out across every assigner via the atomic `SchemaTransaction`, after a recovery snapshot. **Agenda keeps its own sidecar `property_definitions` — untouched.** Page-frontmatter values stay `prop_<ulid>`-keyed, never migrated (clean-slate wipe already ran).

**Tech Stack:** TypeScript, Electron (main/preload/renderer), zod (`shared/schemas.ts` + `shared/properties.ts`), Vitest. Store pattern mirrors `main/io/folds.ts`. Atomic multi-file writes via `main/io/schemaTransaction.ts`. SQLite via the regeneratable index (off the read path).

## Global Constraints

- **Main owns the filesystem; renderer talks only through typed IPC.** IPC never throws — every handler returns `{ ok: true, … } | { ok: false, error }`.
- **`shared/schemas.ts` + `shared/properties.ts` are the cross-process contract** — no fs, no React.
- **Registry = `.nexus/properties.json`**, shape `Record<propId, PropertyDefinition>`. Sidecar `properties` = `string[]` (assignment ids). `CollectionNode.properties` stays `PropertyDefinition[]`.
- **Values stay `prop_<ulid>`-keyed in frontmatter — never migrated.** Only a Delete's scrub touches page files.
- **The renderer is not modified in this plan.** The `schema:*` IPC surface + `window.nexus.schema.*` preload keep their exact signatures; only their main-side implementation is re-backed. UX refinement (assign-existing, Remove-vs-Delete labels, Max Properties) is Plan 2.
- **Agenda (`agendaConfigSidecar.property_definitions`, `agendaTarget` in `crud/schema.ts`) is out of scope** — untouched.
- **Create validates a name against the WHOLE registry; Assign runs NO name-clash check.** (After the flip, `schema:add` can now fail on a *global* name clash — that surfaces through `commit()` in PropertiesPane; the "assign existing instead" nudge is Plan 2.)
- **`schema:delete` becomes non-destructive (unassign).** The def + values survive; the property just leaves the Collection. Global Delete (`deleteProperty`) is built + IPC-exposed here but only surfaced in the UI in Plan 2.
- **`SCHEMA_VERSION` bumps 15 → 16** for the SQLite `property_definitions` change (auto drop+rebuild; nothing reads `sessionDb()`).
- **TDD, each task an independent green commit.** Vitest, temp nexus via `mkdtemp(join(tmpdir(), 'pom-<area>-'))` + `createFolderEntity`. Gate: `npm run typecheck` + `npx vitest run`. Biome auto-formats — don't hand-format.
- **`Result` / `ok` / `fail`:** import from `@shared/result` (real signature `fail(code, message, scope?)` — the optional third arg means the 2-arg form is valid).

---

## File Structure

**Create:**
- `src/main/io/propertiesRegistry.ts` (+ `.test.ts`) — registry store (`.nexus/properties.json`), mirrors `io/folds.ts`.
- `src/main/crud/registryProperty.ts` (+ `.test.ts`) — `createProperty` / `editProperty` / `removeFromRegistry`.
- `src/main/crud/assignment.ts` (+ `.test.ts`) — `assignProperty` / `unassignProperty` / `reorderAssignment` / `assigners`.
- `src/main/crud/deleteProperty.ts` (+ `.test.ts`) — the fan-out global Delete + snapshot.
- `src/shared/__fixtures__/registry.json` — defs for the read-path + pipeline tests.

**Modify:**
- `src/main/paths.ts` — `NEXUS_CONFIG_FILES.properties = 'properties.json'`.
- `src/shared/schemas.ts` — `pageCollectionSidecar.properties`: `z.array(z.looseObject({}))` → `z.array(z.string())`.
- `src/main/readNexus.ts` — load the registry once; join ids→defs in `readPageCollection`.
- `src/main/crud/schema.ts` — remove `PAGE_TARGET` + the 5 collection exports; keep `agendaTarget` + shared helpers; `export { stripPageMember }`.
- `src/main/index.ts` — repoint the 5 `schema:*` handlers to the V2 adapters; drop the now-unused collection imports from `crud/schema.ts`; add a `property:delete` handler; keep `resolveSchemaFolder`.
- `src/main/index/schema.ts` — drop `owning_type_id/kind` from `property_definitions` + its index; `SCHEMA_VERSION` 15 → 16.
- `src/main/index/upsert.ts` + `src/main/index/build.ts` — `upsertPropertyDefinition` loses owner cols; `build.ts:148` populates from `readRegistry`, not `parseDefinitions(csc.properties)`.
- `src/main/mutate.ts` — hoist the 13 `refreshSessionIndex(root)` calls to one in `handleMutate`.
- `src/main/crud/schema.test.ts` — drop the collection cases (covered by the new modules); keep agenda.
- `src/shared/__fixtures__/collection-with-status.json` — `properties` → `["prop_status","prop_when"]`.
- `src/renderer/src/Detail/Views/pipeline/columns.test.ts`, `resolveView.test.ts` — build the schema from the registry fixture + the sidecar's assignment ids (see Task 3). (`shared/views.test.ts` uses `fixture.views`, not `.properties` — no change.)
- `src/main/index/build.test.ts` — its setup imports `addProperty` from `crud/schema` (removed in Task 3); repoint to `createProperty` + `assignProperty`.

**Not modified:** the renderer (`PropertiesPane.tsx`, `ViewPane.tsx`), the preload surface signatures.

---

## Task 1: Registry store (`propertiesRegistry.ts`)

**Files:** Create `src/main/io/propertiesRegistry.ts` + `.test.ts`; Modify `src/main/paths.ts` (add the constant).

**Interfaces — Produces:** `type PropertyRegistry = Record<string, PropertyDefinition>`; `readRegistry(root): Promise<PropertyRegistry>`; `writeRegistry(root, registry): Promise<void>`.

- [ ] **Step 1: Add the paths constant.** In `src/main/paths.ts`, append to `NEXUS_CONFIG_FILES`:

```ts
  viewOrders: 'viewOrders.json',
  properties: 'properties.json'
} as const
```

- [ ] **Step 2: Write the failing test** — `src/main/io/propertiesRegistry.test.ts`:

```ts
import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, writeFile, mkdir } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { readRegistry, writeRegistry } from './propertiesRegistry'
import type { PropertyDefinition } from '@shared/properties'

let root: string
beforeEach(async () => { root = await mkdtemp(join(tmpdir(), 'pom-registry-')) })
afterEach(async () => { await rm(root, { recursive: true, force: true }) })

const def = (id: string, name: string): PropertyDefinition =>
  ({ id, name, type: 'select', select_options: [{ value: 'a', label: 'A', color: 'blue' }] }) as PropertyDefinition

describe('propertiesRegistry', () => {
  it('reads {} when absent', async () => { expect(await readRegistry(root)).toEqual({}) })
  it('round-trips a written registry', async () => {
    const reg = { prop_a: def('prop_a', 'Priority'), prop_b: def('prop_b', 'Status') }
    await writeRegistry(root, reg)
    expect(await readRegistry(root)).toEqual(reg)
  })
  it('drops entries failing the def schema', async () => {
    await mkdir(join(root, '.nexus'), { recursive: true })
    await writeFile(join(root, '.nexus', 'properties.json'),
      JSON.stringify({ prop_a: def('prop_a', 'Priority'), prop_bad: { id: 'prop_bad' } }))
    expect(Object.keys(await readRegistry(root))).toEqual(['prop_a'])
  })
})
```

- [ ] **Step 3: Run — expect FAIL.** `cd React && npx vitest run src/main/io/propertiesRegistry.test.ts`

- [ ] **Step 4: Implement** `src/main/io/propertiesRegistry.ts` (mirrors `io/folds.ts`):

```ts
import { mkdir } from 'node:fs/promises'
import { nexusConfig, nexusDir, NEXUS_CONFIG_FILES } from '../paths'
import { readJsonObject, writeJson } from './atomicWrite'
import { propertyDefinition, type PropertyDefinition } from '@shared/properties'

/** propId → its nexus-wide definition. The shared registry, `.nexus/properties.json`. */
export type PropertyRegistry = Record<string, PropertyDefinition>

const registryPath = (root: string): string => nexusConfig(root, NEXUS_CONFIG_FILES.properties)

/** Lenient read: absent / corrupt → `{}`; drops any entry that fails the def schema. */
export async function readRegistry(root: string): Promise<PropertyRegistry> {
  const obj = await readJsonObject(registryPath(root))
  if (obj === null) return {}
  const out: PropertyRegistry = {}
  for (const [id, value] of Object.entries(obj)) {
    const parsed = propertyDefinition.safeParse(value)
    if (parsed.success) out[id] = parsed.data
  }
  return out
}

/** Overwrite the whole registry (callers read-modify-write). */
export async function writeRegistry(root: string, registry: PropertyRegistry): Promise<void> {
  await mkdir(nexusDir(root), { recursive: true })
  await writeJson(registryPath(root), registry)
}
```

- [ ] **Step 5: Run — expect PASS.** Then `npm run typecheck`.

- [ ] **Step 6: Commit**

```bash
git add src/main/io/propertiesRegistry.ts src/main/io/propertiesRegistry.test.ts src/main/paths.ts
git commit -m "feat(properties): nexus-wide registry store (.nexus/properties.json)"
```

---

## Task 2: Registry-def CRUD (`registryProperty.ts`)

Additive — operates only on the registry, so it lands before the flip. Create validates the name against the **whole registry**.

**Files:** Create `src/main/crud/registryProperty.ts` + `.test.ts`.

**Interfaces — Produces:** `createProperty(root, def): Promise<Result<{ id: string }>>`; `editProperty(root, propertyId, changes): Promise<Result<null>>`; `removeFromRegistry(root, propertyId): Promise<Result<null>>`.

- [ ] **Step 1: Write the failing test** — `src/main/crud/registryProperty.test.ts`:

```ts
import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { createProperty, editProperty, removeFromRegistry } from './registryProperty'
import { readRegistry } from '../io/propertiesRegistry'
import type { PropertyDefinition } from '@shared/properties'

let root: string
beforeEach(async () => { root = await mkdtemp(join(tmpdir(), 'pom-regcrud-')) })
afterEach(async () => { await rm(root, { recursive: true, force: true }) })
const def = (over: Partial<PropertyDefinition> & { name: string; type: PropertyDefinition['type'] }) =>
  ({ id: '', ...over }) as PropertyDefinition

describe('createProperty', () => {
  it('mints prop_, seeds status groups, persists to the registry', async () => {
    const r = await createProperty(root, def({ name: 'Stage', type: 'status' }))
    expect(r.ok).toBe(true); if (!r.ok) return
    expect(r.value.id.startsWith('prop_')).toBe(true)
    expect((await readRegistry(root))[r.value.id].status_groups?.map((g) => g.id)).toEqual(['upcoming', 'in_progress', 'done'])
  })
  it('rejects a name clashing anywhere in the registry (case-insensitive)', async () => {
    await createProperty(root, def({ name: 'Priority', type: 'select' }))
    expect((await createProperty(root, def({ name: 'priority', type: 'number' }))).ok).toBe(false)
  })
})
describe('editProperty', () => {
  it('renames in place, keeping the id', async () => {
    const c = await createProperty(root, def({ name: 'Old', type: 'number' })); if (!c.ok) return
    expect((await editProperty(root, c.value.id, { name: 'New' })).ok).toBe(true)
    expect((await readRegistry(root))[c.value.id].name).toBe('New')
  })
  it('rejects renaming onto another def', async () => {
    await createProperty(root, def({ name: 'Alpha', type: 'number' }))
    const b = await createProperty(root, def({ name: 'Beta', type: 'number' })); if (!b.ok) return
    expect((await editProperty(root, b.value.id, { name: 'Alpha' })).ok).toBe(false)
  })
})
describe('removeFromRegistry', () => {
  it('drops the def', async () => {
    const c = await createProperty(root, def({ name: 'Temp', type: 'number' })); if (!c.ok) return
    expect((await removeFromRegistry(root, c.value.id)).ok).toBe(true)
    expect(await readRegistry(root)).toEqual({})
  })
})
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement** `src/main/crud/registryProperty.ts`:

```ts
import { readRegistry, writeRegistry } from '../io/propertiesRegistry'
import { validateDefinition, validateName } from '../properties/schema'
import { mintPropertyId } from '../ids'
import { defaultStatusSeed, defaultSelectSeed, type PropertyDefinition } from '@shared/properties'
import { ok, fail, type Result } from '@shared/result'

function seeded(def: PropertyDefinition): PropertyDefinition {
  let d = def
  if (d.type === 'status' && d.status_groups === undefined) d = { ...d, status_groups: defaultStatusSeed() }
  if ((d.type === 'select' || d.type === 'multi_select') && (d.select_options?.length ?? 0) === 0)
    d = { ...d, select_options: defaultSelectSeed() }
  return d
}

export async function createProperty(root: string, def: PropertyDefinition): Promise<Result<{ id: string }>> {
  const registry = await readRegistry(root)
  const candidate = seeded({ ...def, id: def.id || mintPropertyId() })
  const v = validateDefinition(candidate, Object.values(registry)) // name vs the WHOLE registry
  if (!v.ok) return v
  await writeRegistry(root, { ...registry, [candidate.id]: candidate })
  return ok({ id: candidate.id })
}

export async function editProperty(
  root: string, propertyId: string, changes: Partial<PropertyDefinition>
): Promise<Result<null>> {
  const registry = await readRegistry(root)
  const current = registry[propertyId]
  if (!current) return fail('not-found', 'Property not found.')
  const next = seeded({ ...current, ...changes, id: propertyId })
  if (next.name !== current.name) {
    const v = validateName(next.name, Object.values(registry), propertyId)
    if (!v.ok) return v
  }
  await writeRegistry(root, { ...registry, [propertyId]: next })
  return ok(null)
}

export async function removeFromRegistry(root: string, propertyId: string): Promise<Result<null>> {
  const registry = await readRegistry(root)
  if (!registry[propertyId]) return fail('not-found', 'Property not found.')
  const next = { ...registry }; delete next[propertyId]
  await writeRegistry(root, next)
  return ok(null)
}
```

Confirm `@shared/result`'s exact `fail` codes — reuse an existing code (`'invalid-property'` / `'not-found'`) matching `main/properties/schema.ts`.

- [ ] **Step 4: Run — expect PASS.** Then `npm run typecheck`.

- [ ] **Step 5: Commit**

```bash
git add src/main/crud/registryProperty.ts src/main/crud/registryProperty.test.ts
git commit -m "feat(properties): registry-def CRUD — create/edit validate against the whole registry"
```

---

## Task 3: The flip — sidecar `string[]`, `readNexus` join, assignment ops, re-backed `schema:*`

**One atomic task by necessity:** flipping the sidecar semantics can't coexist with the old collection CRUD, and the live `PropertiesPane` must keep working. Deliverable: a Collection's schema resolves from the registry via its assignment ids, `PropertiesPane`'s create/rename/delete are registry+assignment-backed, agenda is untouched, everything green.

**Files:** Modify `shared/schemas.ts`, `main/readNexus.ts`, `main/crud/schema.ts`, `main/index.ts`, `main/crud/schema.test.ts`, `main/index/build.test.ts`, the fixture + 2 pipeline tests; Create `main/crud/assignment.ts` + `.test.ts`, `shared/__fixtures__/registry.json`.

**Interfaces — Produces:** `resolveAssignedSchema(ids, registry): PropertyDefinition[] | undefined` (from `readNexus.ts`); `assignProperty(collectionFolder, propertyId)`, `unassignProperty(collectionFolder, propertyId)`, `reorderAssignment(collectionFolder, propertyId, toIndex)` (from `assignment.ts`), each `Promise<Result<null>>`.

- [ ] **Step 1: Assignment ops + tests** — Create `src/main/crud/assignment.test.ts`:

```ts
import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { assignProperty, unassignProperty, reorderAssignment } from './assignment'
import { createFolderEntity } from './folderEntity'
import { readSidecar } from '../sidecarIO'
import { pageCollectionSidecar } from '@shared/schemas'

let root: string, notes: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-assign-'))
  const c = await createFolderEntity(root, 'collection', 'Notes')
  if (!c.ok) throw new Error('setup failed')
  notes = c.value.path // NOTE: confirm createFolderEntity's Result shape (folderEntity.ts) — adjust if not `.value.path`
})
afterEach(async () => { await rm(root, { recursive: true, force: true }) })
const ids = async (folder: string): Promise<string[]> =>
  ((await readSidecar(folder, 'collection', pageCollectionSidecar))?.properties as string[]) ?? []

it('assign appends + is idempotent', async () => {
  await assignProperty(notes, 'prop_x'); await assignProperty(notes, 'prop_x')
  expect(await ids(notes)).toEqual(['prop_x'])
})
it('unassign removes just that id', async () => {
  await assignProperty(notes, 'prop_x'); await assignProperty(notes, 'prop_y')
  await unassignProperty(notes, 'prop_x')
  expect(await ids(notes)).toEqual(['prop_y'])
})
it('reorder moves within the assignment array', async () => {
  await assignProperty(notes, 'prop_a'); await assignProperty(notes, 'prop_b'); await assignProperty(notes, 'prop_c')
  await reorderAssignment(notes, 'prop_c', 0)
  expect(await ids(notes)).toEqual(['prop_c', 'prop_a', 'prop_b'])
})
```

Run — expect FAIL. Then create `src/main/crud/assignment.ts`:

```ts
import { readSidecar, writeSidecar } from '../sidecarIO'
import { pageCollectionSidecar } from '@shared/schemas'
import { ok, fail, type Result } from '@shared/result'

async function read(folder: string): Promise<{ sidecar: Record<string, unknown>; ids: string[] } | null> {
  const sidecar = await readSidecar(folder, 'collection', pageCollectionSidecar)
  if (sidecar === null) return null
  return { sidecar: sidecar as Record<string, unknown>, ids: (sidecar.properties as string[] | undefined) ?? [] }
}
const write = async (folder: string, sidecar: Record<string, unknown>, ids: string[]): Promise<void> =>
  writeSidecar(folder, 'collection', { ...sidecar, properties: ids })

export async function assignProperty(collectionFolder: string, propertyId: string): Promise<Result<null>> {
  const r = await read(collectionFolder)
  if (!r) return fail('not-found', 'Collection not found.')
  if (r.ids.includes(propertyId)) return ok(null) // dedup / idempotent
  await write(collectionFolder, r.sidecar, [...r.ids, propertyId])
  return ok(null)
}
export async function unassignProperty(collectionFolder: string, propertyId: string): Promise<Result<null>> {
  const r = await read(collectionFolder)
  if (!r) return fail('not-found', 'Collection not found.')
  await write(collectionFolder, r.sidecar, r.ids.filter((id) => id !== propertyId))
  return ok(null)
}
export async function reorderAssignment(collectionFolder: string, propertyId: string, toIndex: number): Promise<Result<null>> {
  const r = await read(collectionFolder)
  if (!r) return fail('not-found', 'Collection not found.')
  const from = r.ids.indexOf(propertyId)
  if (from < 0) return fail('not-found', 'Property not assigned.')
  const next = [...r.ids]; const [m] = next.splice(from, 1)
  next.splice(Math.min(Math.max(toIndex, 0), next.length), 0, m)
  await write(collectionFolder, r.sidecar, next)
  return ok(null)
}
```

**This test only passes once the sidecar zod is flipped (Step 2)** — `readSidecar` parses `properties` via `pageCollectionSidecar`, which currently rejects strings. So run it after Step 2.

- [ ] **Step 2: Flip the sidecar schema.** In `src/shared/schemas.ts` (`pageCollectionSidecar`):

```ts
  // V2: nexus-wide assignment ids (was a PropertyDefinition[] inline schema)
  properties: z.array(z.string()).optional(),
```

- [ ] **Step 3: `readNexus` registry load + join.** In `src/main/readNexus.ts`:

```ts
import { readRegistry, type PropertyRegistry } from './io/propertiesRegistry'

/** effectiveSchema(C): assignment ids → their registry defs, in order; drops dangling refs. */
export function resolveAssignedSchema(ids: unknown, registry: PropertyRegistry): PropertyDefinition[] | undefined {
  if (!Array.isArray(ids)) return undefined
  const defs = ids.filter((id): id is string => typeof id === 'string')
    .map((id) => registry[id]).filter((d): d is PropertyDefinition => Boolean(d))
  return defs.length ? defs : undefined
}
```

In `readNexus()` singleton block (~line 286) add `const registry = await readRegistry(root)`. Thread `registry` into `readPageCollection` (single call site — `readNexus.ts:332`; add a `registry: PropertyRegistry` param). At the collection assembly (readNexus.ts:217-219) replace the raw cast with `properties: resolveAssignedSchema(meta.properties, registry)`. (Sets don't carry properties — no set-path change; the renderer's ancestor-walk inheritance is unaffected.)

- [ ] **Step 4: Split the fixture.** Create `src/shared/__fixtures__/registry.json` with the two defs currently inline in `collection-with-status.json` (`prop_status` full status def + `prop_when` datetime). Change `collection-with-status.json`'s `properties` to `["prop_status", "prop_when"]` (keep `id`, `_foreign_collection_key`, `views`).

Update the pipeline tests that read defs from the fixture. `columns.test.ts:21` currently does:

```ts
const fixtureSchema = fixture.properties.map((p) => propertyDefinition.parse(p))
```

Replace with a registry-resolve:

```ts
import registry from '@shared/__fixtures__/registry.json'
const fixtureSchema = (fixture.properties as string[]).map((id) => propertyDefinition.parse((registry as Record<string, unknown>)[id]))
```

Apply the same change in `resolveView.test.ts` wherever it maps `fixture.properties` to defs. (`shared/views.test.ts` reads `fixture.views` only — no change.)

- [ ] **Step 5: Remove the old collection CRUD; keep agenda.** In `src/main/crud/schema.ts`: delete `PAGE_TARGET` and the 5 collection exports (`addProperty`/`renameProperty`/`reorderProperty`/`deleteProperty`/`changePropertyType`). Keep `agendaTarget`, `stripAgendaMember`, the shared `readSchema`/`nextSidecar`/`stageMemberStrips`, and the agenda exports (they partial-apply `agendaTarget`, not `PAGE_TARGET` — so they compile unchanged). Add `export { stripPageMember }` (Task 4 reuses it). In `src/main/index.ts`: remove the now-dead imports of the five collection functions from `crud/schema.ts`.

- [ ] **Step 6: Re-back the `schema:*` handlers with V2 adapters.** In `src/main/index.ts`, keep `resolveSchemaFolder`; rewrite the five handlers to delegate to registry+assignment ops (keep the exact IPC names/args PropertiesPane calls):

```ts
// schema:add(containerPath, def) — create in the registry, then assign to this collection
ipcMain.handle('schema:add', async (_e, containerPath: unknown, def: unknown) => {
  try {
    const f = await resolveSchemaFolder(containerPath); if (!f.ok) return f
    const root = sessionRoot(); if (root === null) return { ok: false, error: 'No nexus is open.' }
    const parsed = propertyDefinition.safeParse(def); if (!parsed.success) return { ok: false, error: 'Invalid property definition.' }
    const created = await createProperty(root, parsed.data); if (!created.ok) return { ok: false, error: created.error.message }
    const assigned = await assignProperty(f.folder, created.value.id); if (!assigned.ok) return { ok: false, error: assigned.error.message }
    return { ok: true, id: created.value.id }
  } catch (e) { return { ok: false, error: e instanceof Error ? e.message : String(e) } }
})
// schema:rename(containerPath, id, name) → editProperty(root, id, { name })
// schema:changeType(containerPath, id, newType, opts) → editProperty(root, id, { type: newType })  (global; lossy cross-assigner strip is Plan 2)
// schema:reorder(containerPath, id, toIndex) → reorderAssignment(folder, id, toIndex)
// schema:delete(containerPath, id) → unassignProperty(folder, id)  (non-destructive; global Delete is property:delete, Task 4)
```

Write the other four following the same envelope (`rename`/`changeType` key off `sessionRoot()`; `reorder`/`delete` resolve the folder). Import `createProperty`/`editProperty` from `crud/registryProperty`, `assignProperty`/`unassignProperty`/`reorderAssignment` from `crud/assignment`.

- [ ] **Step 7: Trim `crud/schema.test.ts` + repoint `build.test.ts`.** Delete the collection `addProperty`/`renameProperty`/`reorderProperty`/`deleteProperty`/`changePropertyType` describe-blocks (now covered by `registryProperty.test.ts` + `assignment.test.ts`); keep any agenda coverage. In `src/main/index/build.test.ts`: its setup imports `addProperty` from `crud/schema` (removed in Step 5). Replace with `import { createProperty } from '../crud/registryProperty'` + `import { assignProperty } from '../crud/assignment'`, and repoint each setup call (`await addProperty(collFolder, { name, type })` → `const r = await createProperty(root, { id: '', name, type }); if (r.ok) await assignProperty(collFolder, r.value.id)`).

- [ ] **Step 8: Add the read-path test** to `src/main/readNexus.test.ts` (using its `w()`/`mkdtemp` harness):

```ts
it('resolves a collection schema from the registry via assignment ids', async () => {
  const root = await mkdtemp(join(tmpdir(), 'pom-readnexus-v2-'))
  w(join(root, '.nexus', 'nexus.json'), JSON.stringify({ id: 'nx' }))
  w(join(root, '.nexus', 'properties.json'), JSON.stringify({
    prop_a: { id: 'prop_a', name: 'Priority', type: 'select', select_options: [{ value: 'hi', label: 'High', color: 'red' }] },
    prop_b: { id: 'prop_b', name: 'Done', type: 'checkbox' } }))
  w(join(root, 'Notes', '_pagecollection.json'), JSON.stringify({ id: 'col_notes', properties: ['prop_a', 'prop_gone', 'prop_b'] }))
  const tree = await readNexus(root)
  const notes = tree.collections.find((c) => c.id === 'col_notes')!
  expect(notes.properties?.map((d) => d.id)).toEqual(['prop_a', 'prop_b']) // dangling 'prop_gone' dropped
  await rm(root, { recursive: true, force: true })
})
```

- [ ] **Step 9: Full green gate.** Run: `npx vitest run && npm run typecheck`. Fix any pipeline test still reading defs straight from the sidecar fixture (Step 4). Do not proceed until the whole suite + both `tsc` passes are green.

- [ ] **Step 10: Commit**

```bash
git add src/shared/schemas.ts src/main/readNexus.ts src/main/crud/schema.ts src/main/crud/assignment.ts src/main/crud/assignment.test.ts src/main/index.ts src/main/crud/schema.test.ts src/main/index/build.test.ts src/main/readNexus.test.ts src/shared/__fixtures__/ src/renderer/src/Detail/Views/pipeline/columns.test.ts src/renderer/src/Detail/Views/pipeline/resolveView.test.ts
git commit -m "feat(properties): registry+assignment model — flip sidecar to ids, re-back schema:* with V2 ops"
```

---

## Task 4: `assigners` + fan-out Delete + snapshot

Global Delete: snapshot every value → strip it from every assigner's pages + drop the id from every assignment → remove the def, one atomic `SchemaTransaction`. Exposed as `property:delete` (UI in Plan 2).

**Files:** Modify `src/main/crud/assignment.ts` (+ `assigners`); Create `src/main/crud/deleteProperty.ts` + `.test.ts`; Modify `src/main/index.ts` (+ `property:delete` handler) + `src/preload/index.ts` (+ `property.delete`) + the `window.nexus` type.

**Interfaces — Produces:** `assigners(root, propertyId): Promise<string[]>`; `deleteProperty(root, propertyId): Promise<Result<null>>`.

- [ ] **Step 1: `assigners` test + impl.** Add to `assignment.test.ts` a two-collection case asserting `assigners(root, 'prop_shared')` returns both folders and `assigners(root, 'prop_only')` returns one. Implement in `assignment.ts`:

```ts
import { join } from 'node:path'
import { readNexus } from '../readNexus'
import type { CollectionNode, SetNode } from '@shared/types'

/** Absolute folder paths of every Collection whose sidecar array holds propertyId (raw ids, not resolved defs). */
export async function assigners(root: string, propertyId: string): Promise<string[]> {
  const tree = await readNexus(root)
  const out: string[] = []
  const visit = async (node: CollectionNode | SetNode): Promise<void> => {
    if (node.kind === 'collection') {
      const r = await read(join(root, node.path))
      if (r?.ids.includes(propertyId)) out.push(join(root, node.path))
    }
    for (const s of node.sets ?? []) await visit(s)
  }
  for (const c of tree.collections) await visit(c)
  return out
}
```

(`read` is the private helper from Step 1 of Task 3. Confirm `CollectionNode.sets`/`.path`/`.kind` + `tree.collections` in `shared/types.ts` — verified present.)

- [ ] **Step 2: Delete test** — `src/main/crud/deleteProperty.test.ts`:

```ts
import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile, readdir } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { deleteProperty } from './deleteProperty'
import { createProperty } from './registryProperty'
import { assignProperty } from './assignment'
import { createFolderEntity } from './folderEntity'
import { createPage } from './page'
import { updatePageProperty } from './page'
import { readRegistry } from '../io/propertiesRegistry'

let root: string, notes: string, tasks: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-del-'))
  const a = await createFolderEntity(root, 'collection', 'Notes'); const b = await createFolderEntity(root, 'collection', 'Tasks')
  if (!a.ok || !b.ok) throw new Error('setup'); notes = a.value.path; tasks = b.value.path
})
afterEach(async () => { await rm(root, { recursive: true, force: true }) })

it('scrubs the value from every assigner, drops the def + assignments, and snapshots', async () => {
  const c = await createProperty(root, { id: '', name: 'Priority', type: 'select',
    select_options: [{ value: 'hi', label: 'High', color: 'red' }] } as any)
  if (!c.ok) return; const id = c.value.id
  await assignProperty(notes, id); await assignProperty(tasks, id)
  const p1 = await createPage(notes, 'A'); const p2 = await createPage(tasks, 'B')
  if (!p1.ok || !p2.ok) return
  await updatePageProperty(join(root, p1.value.path), id, { kind: 'select', value: 'hi' } as any)
  await updatePageProperty(join(root, p2.value.path), id, { kind: 'select', value: 'hi' } as any)

  expect((await deleteProperty(root, id)).ok).toBe(true)
  expect((await readRegistry(root))[id]).toBeUndefined()
  expect(await readFile(join(root, p1.value.path), 'utf8')).not.toContain(id)
  expect(await readFile(join(root, p2.value.path), 'utf8')).not.toContain(id)
  expect((await readdir(join(root, '.trash'))).some((f) => f.includes('property'))).toBe(true)
})
```

(Confirm `createPage`'s Result shape + `updatePageProperty`'s `PropertyValue` arg against `crud/page.ts:92` — adjust the `{ kind, value }` literal to the real `PropertyValue` tag.)

- [ ] **Step 3: Implement** `src/main/crud/deleteProperty.ts`:

```ts
import { join } from 'node:path'
import { readFile, mkdir, writeFile } from 'node:fs/promises'
import { readRegistry } from '../io/propertiesRegistry'
import { removeFromRegistry } from './registryProperty'
import { assigners } from './assignment'
import { SchemaTransaction } from '../io/schemaTransaction'
import { stripPageMember } from './schema'
import { readSidecar } from '../sidecarIO'
import { pageCollectionSidecar } from '@shared/schemas'
import { listMarkdownFiles } from '../io/walk'
import { SIDECAR_FILENAME } from '../paths'
import { serializeJson, readJsonObject } from '../io/atomicWrite'
import { readFrontmatterFields } from '../io/pageFile'
import { ok, fail, type Result } from '@shared/result'

async function snapshot(root: string, propertyId: string, folders: string[]): Promise<void> {
  const registry = await readRegistry(root)
  const values: Record<string, unknown> = {}
  for (const folder of folders)
    for (const file of await listMarkdownFiles(folder)) {
      const props = readFrontmatterFields(await readFile(file, 'utf8')).properties as Record<string, unknown> | undefined
      if (props && propertyId in props) values[file] = props[propertyId]
    }
  const trash = join(root, '.trash'); await mkdir(trash, { recursive: true })
  const stamp = new Date().toISOString().replace(/[:.]/g, '-')
  await writeFile(join(trash, `${stamp}__property-${propertyId}.json`),
    serializeJson({ propertyId, def: registry[propertyId] ?? null, values }))
}

export async function deleteProperty(root: string, propertyId: string): Promise<Result<null>> {
  const registry = await readRegistry(root)
  if (!registry[propertyId]) return fail('not-found', 'Property not found.')
  const folders = await assigners(root, propertyId)
  await snapshot(root, propertyId, folders)
  const tx = new SchemaTransaction()
  for (const folder of folders) {
    const sidecar = await readSidecar(folder, 'collection', pageCollectionSidecar)
    if (sidecar) {
      const ids = ((sidecar.properties as string[] | undefined) ?? []).filter((id) => id !== propertyId)
      tx.stage(join(folder, SIDECAR_FILENAME.collection), serializeJson({ ...sidecar, properties: ids }))
    }
    for (const file of await listMarkdownFiles(folder)) {
      const stripped = stripPageMember(await readFile(file, 'utf8'), propertyId)
      if (stripped !== null) tx.stage(file, stripped)
    }
  }
  await tx.commit()
  return removeFromRegistry(root, propertyId)
}
```

(`readJsonObject` import can drop if unused. Confirm `stripPageMember` is exported from `crud/schema.ts` per Task 3 Step 5.)

- [ ] **Step 4: `property:delete` IPC.** In `src/main/index.ts` add a `property:delete` handler (keys off `sessionRoot()` → `deleteProperty(root, propertyId)` → envelope). In `src/preload/index.ts` add `property: { delete: (propertyId: string) => ipcRenderer.invoke('property:delete', propertyId) }` and extend the `window.nexus` ambient type. (Locate the real ambient type — grep `interface .*nexus` / `window.nexus` in `renderer/src`.)

- [ ] **Step 5: Run — expect PASS.** Then `npm run typecheck`.

- [ ] **Step 6: Commit**

```bash
git add src/main/crud/deleteProperty.ts src/main/crud/deleteProperty.test.ts src/main/crud/assignment.ts src/main/crud/assignment.test.ts src/main/index.ts src/preload/index.ts
git commit -m "feat(properties): global delete — assigners, snapshot, strip across all, property:delete IPC"
```

---

## Task 5: SQLite — drop owner-scoping, populate from the registry

**Files:** Modify `src/main/index/schema.ts`, `upsert.ts`, `build.ts`.

- [ ] **Step 1: DDL + version.** `src/main/index/schema.ts`: `SCHEMA_VERSION = 16`; remove `owning_type_id`/`owning_type_kind` from the `property_definitions` CREATE TABLE (lines 97-106) and delete `idx_property_definitions_owning_type` (line 117).

- [ ] **Step 2: Upsert.** `src/main/index/upsert.ts`: drop `owningTypeId`/`owningTypeKind` from the `upsertPropertyDefinition` param + the row object.

- [ ] **Step 3: Populate from the registry.** `src/main/index/build.ts:148` currently does `defs: parseDefinitions(csc?.properties)` (per-collection). Replace the property-definitions population with one pass over `readRegistry(root)`, upserting each def (id, name, type, config from the def, `position` = index, `modifiedAt`). No owner.

- [ ] **Step 4: Verify.** `npm run typecheck && npx vitest run src/main/index` (index tests rebuild on the v16 bump; `sessionDb()` still has no readers).

- [ ] **Step 5: Commit**

```bash
git add src/main/index/schema.ts src/main/index/upsert.ts src/main/index/build.ts
git commit -m "feat(properties): SQLite property_definitions drops owner-scoping (v16), populates from registry"
```

---

## Task 6: Ride-along cleanup — hoist `refreshSessionIndex`

**Files:** Modify `src/main/mutate.ts`.

- [ ] **Step 1: Test/adjust.** If `mutate.test.ts` exists, assert a representative op still refreshes after the hoist (spy on `refreshSessionIndex`, expect one call per successful `handleMutate`).

- [ ] **Step 2: Hoist.** Remove the 13 `void refreshSessionIndex(root)` lines from the case bodies (140, 158, 168, 192, 199, 216, 283, 325, 345, 362, 377, 387, 395) and call it once in `handleMutate`:

```ts
export async function handleMutate(req: MutateRequest, deps: MutateDeps): Promise<MutateResult> {
  const root = sessionRoot()
  if (root === null) return fault('No nexus is open.')
  try {
    const result = await dispatch(req, deps, root)
    if (result.ok) void refreshSessionIndex(root)
    return result
  } catch (e) {
    return fault(e instanceof Error ? e.message : String(e))
  }
}
```

- [ ] **Step 3: Verify.** `npm run typecheck && npx vitest run src/main/mutate.test.ts` (if present) `&& rg -n "refreshSessionIndex" src/main/mutate.ts` (expect the import + one call only).

- [ ] **Step 4: Commit**

```bash
git add src/main/mutate.ts
git commit -m "refactor(mutate): hoist refreshSessionIndex to one post-dispatch call"
```

---

## Self-Review

**Green-per-task safety** (the round-1 blocker): the renderer is never broken — `schema:*` keeps its exact signatures; only its main-side impl changes (Task 3 Step 6). PropertiesPane's `schema` prop is registry-resolved `PropertyDefinition[]`, unchanged. The flip is one atomic task so the sidecar-semantics change never straddles a commit boundary.

**Spec coverage** (V2 Decision Log → task): A-1/A-3 registry + `string[]` → Tasks 1,3 · B-1 shared defs → Task 2 (validateDefinition) · E-1 main-resolve + `.filter(Boolean)` + `assigners` scan → Tasks 3,4 · F-3 create-vs-whole-registry, assign dedup no-name-check → Tasks 2,3 · C-1/C-2 Delete-only + snapshot-in-trash → Task 4 (and `schema:delete`→unassign is the non-destructive daily op) · F-5 SQLite v16 → Task 5 · optimistic deferred (load-after-write is what PropertiesPane already does) → no task · `refreshSessionIndex` hoist → Task 6. Agenda untouched throughout.

**Deferred to Plan 2 (assign-surface UX):** assign-existing picker, Remove-vs-Delete labels, the "create clashes globally → offer assign existing" nudge, lossy `changeType` cross-assigner value-strip, drag-reorder UI, and the **Max Properties stop-and-ask**. The Inspector gate (F-6) lands when the Inspector is built.

**Groundings the implementer confirms per task** (each a known local, verified present in round 1 unless noted): `createFolderEntity`'s `Result<{ path }>` shape (`.value.path`); `createPage`'s Result shape + `updatePageProperty`'s `PropertyValue` tag (`crud/page.ts:92`); the `window.nexus` ambient-type location for Task 4 Step 4; `@shared/result`'s exact `fail` codes; `SchemaTransaction.stage/commit`, `listMarkdownFiles`, `readFrontmatterFields`, `serializeJson` (all confirmed real in round 1).
