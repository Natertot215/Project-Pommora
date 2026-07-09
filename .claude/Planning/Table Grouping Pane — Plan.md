# Table Grouping Pane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the table view's Grouping leaf — Group By / Order / Date By / Sub-Group authoring over the existing pipeline — plus the three net-new pipeline mechanisms it exposes (sub-group resolver, ungrouped placement, Location order mode).

**Architecture:** Model-first: extend the structural `GroupConfig` + `SavedView` (Task 1), land the three pipeline mechanisms as pure, tested stages (Tasks 2–4), then the table render/write changes (Tasks 5–6), then the pane UI behind both doors (Tasks 7–10), then docs (Task 11). Every write rides the existing `saveViewAdopting → views:save` path; fs-order writes ride the existing `mutate` ops. Spec: `.claude/Planning/Table Grouping Pane — Decision Log.md` (certification-clean; decision tags like C-1a/E-4 below refer to it).

**Tech Stack:** React 19 + TS in the renderer; zod codec in `src/shared`; Vitest (jsdom + `createRoot`/`act` — NOT @testing-library); vanilla-extract + menu primitives for the pane.

## Global Constraints

- Work on branch `table-grouping-pane` off `main`. Repo root for all commands: `Pommora/`.
- Gates after every task: `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (the only type gate) and `npx vitest run` (background them; never launch the GUI with `ELECTRON_RUN_AS_NODE` set). `npm run build` at Task 12 only.
- Biome auto-formats on write via hook — NEVER run it; if an Edit fails on whitespace, re-read and retry.
- Commit after each task with **explicit-path staging** (`git add <files>` — never `-A`; parallel sessions are common).
- Colors/dimensions only via `design-system` tokens; no raw hex/px in new CSS.
- Comments: why-only, 1–2 lines. No keyboard shortcuts. Title-Case UI action labels; footing labels use existing footing classes.
- On-disk keys are snake_case (Swift-parity convention).
- All grouping config is per-view (sidecar `views[]`) — never personalization.

---

## File Map

| File | Role in this plan |
| --- | --- |
| `src/shared/views.ts` (+ `views.test.ts`) | GroupConfig structural extension, SavedView fields, lenient decode |
| `src/renderer/src/Detail/Views/pipeline/group.ts` (+ `group.test.ts`) | placement branching, sub-group resolver |
| `src/renderer/src/Detail/Views/pipeline/resolveView.ts` (+ `resolveView.test.ts`) | Location-order gate, placement pass-through |
| `src/renderer/src/Detail/Views/PropertyEditing/formatValue.ts` (+ new test) | `formatBucketLabel` date-heading helper |
| `src/renderer/src/Detail/Views/Table/GroupHeader.tsx` | sub-group glyphs, formatted date headings, scoped "+" |
| `src/renderer/src/Detail/Views/Table/TableView.tsx` (+ `bandCommits.test.tsx`) | drop-router mode branch, sub-order writes |
| `src/main/valueMenu.ts` (new) + `src/main/index.ts` + `src/preload/index.ts` | footing native value-pick IPC |
| `src/renderer/src/Components/Detail/GroupingPane.tsx` (new) | the pane |
| `src/renderer/src/Components/Detail/SettingsPane.tsx` + `ViewSettings.tsx` | wire both doors |
| `.claude/Features/Views.md` + `TableView.md` + `.claude/History.md` | reconciliation (H-1..H-3) |

---

### Task 1: Model — GroupConfig Extension + SavedView Fields

**Files:**
- Modify: `Pommora/src/shared/views.ts` (types ~L34–77, decoder ~L144–177, codec ~L181–208)
- Test: `Pommora/src/shared/views.test.ts`

**Interfaces (Produces):**
```ts
export type StructuralOrderMode = 'custom' | 'location'          // STRUCTURAL_ORDER_MODES
export type DateSeparator = 'dash' | 'slash'                     // DATE_SEPARATORS
export interface SubGroupConfig {
  property_id: string
  order_mode: GroupOrderMode        // existing 'configured' | 'reversed' | 'manual'
  order?: string[]
  date_granularity?: DateGranularity
}
// GroupConfig structural variant becomes:
//   { kind: 'structural'; order_mode?: StructuralOrderMode; sub_group?: SubGroupConfig }
// SavedView gains: ungrouped_placement?: EmptyPlacement; date_separator?: DateSeparator
```
Defaults on absence (E-1/E-2): `order_mode` → `'custom'` semantics, no `sub_group` → plain structural, `ungrouped_placement` → `'bottom'`, `date_separator` → `'dash'`.

- [ ] **Step 1: Write the failing decode tests** — append to `src/shared/views.test.ts` (match its existing describe style):

```ts
describe('decodeGroupConfig structural extension', () => {
  it('decodes order_mode + sub_group on a structural group', () => {
    const g = decodeGroupConfig({
      kind: 'structural',
      order_mode: 'location',
      sub_group: { property_id: 'p1', order_mode: 'manual', order: ['a', 'b'], date_granularity: 'week' }
    })
    expect(g).toEqual({
      kind: 'structural',
      order_mode: 'location',
      sub_group: { property_id: 'p1', order_mode: 'manual', order: ['a', 'b'], date_granularity: 'week' }
    })
  })
  it('a bare structural decodes with no extension fields (legacy sidecars unchanged)', () => {
    expect(decodeGroupConfig({ kind: 'structural' })).toEqual({ kind: 'structural' })
  })
  it('malformed extension fields drop without poisoning the group', () => {
    const g = decodeGroupConfig({ kind: 'structural', order_mode: 'nope', sub_group: { order_mode: 'manual' } })
    expect(g).toEqual({ kind: 'structural' }) // bad enum drops; sub_group without property_id drops whole
  })
  it('savedView round-trips ungrouped_placement + date_separator', () => {
    const v = savedView.parse({ id: 'view_x', name: 'T', type: 'table', property_order: [], hidden_properties: [], ungrouped_placement: 'top', date_separator: 'slash' })
    expect(v.ungrouped_placement).toBe('top')
    expect(v.date_separator).toBe('slash')
  })
})
```

- [ ] **Step 2:** Run `npx vitest run src/shared/views.test.ts` → expect the four new tests FAIL (fields stripped / properties absent).

- [ ] **Step 3: Implement.** In `views.ts`:

Add beside the existing const arrays (~L40):
```ts
const STRUCTURAL_ORDER_MODES = ['custom', 'location'] as const
export type StructuralOrderMode = (typeof STRUCTURAL_ORDER_MODES)[number]
const DATE_SEPARATORS = ['dash', 'slash'] as const
export type DateSeparator = (typeof DATE_SEPARATORS)[number]

/** Location-mode sub-grouping — a property bucketing INSIDE each top-level set band (E-1). */
export interface SubGroupConfig {
  property_id: string
  order_mode: GroupOrderMode
  order?: string[]
  date_granularity?: DateGranularity
}
```

Extend the union's structural arm (L66–67):
```ts
export type GroupConfig =
  | { kind: 'structural'; order_mode?: StructuralOrderMode; sub_group?: SubGroupConfig }
  | { kind: 'flat' }
  | { /* property arm unchanged */ }
```

Add to `SavedView` (after `group_order`, keeping the snake_case key comments style):
```ts
  /** Global ungrouped-region placement — one view-level knob for every ungrouped tail (D-7/E-2);
   *  the property config's empty_placement stays decode parity. Absent = bottom. */
  ungrouped_placement?: EmptyPlacement
  /** Date group-heading separator under numeric formats (D-8). Absent = dash. */
  date_separator?: DateSeparator
```

In `decodeGroupConfig`, add set + helper above the switch and replace the two `{ kind: 'structural' }` returns (L167 and the L173/L175 fallbacks) with `asStructural()`:
```ts
const STRUCTURAL_ORDER_MODE_SET = new Set<string>(STRUCTURAL_ORDER_MODES)

const asStructural = (): GroupConfig => {
  const order_mode = asEnum<StructuralOrderMode>(obj.order_mode, STRUCTURAL_ORDER_MODE_SET)
  const sg = obj.sub_group
  let sub_group: SubGroupConfig | undefined
  if (sg !== null && typeof sg === 'object' && !Array.isArray(sg)) {
    const s = sg as Record<string, unknown>
    if (typeof s.property_id === 'string' && s.property_id !== '') {
      const order = Array.isArray(s.order) ? (s.order.filter((x) => typeof x === 'string') as string[]) : undefined
      const granularity = asEnum<DateGranularity>(s.date_granularity, DATE_GRANULARITY_SET)
      sub_group = {
        property_id: s.property_id,
        order_mode: asEnum<GroupOrderMode>(s.order_mode, GROUP_ORDER_MODE_SET) ?? 'configured',
        ...(order !== undefined ? { order } : {}),
        ...(granularity !== undefined ? { date_granularity: granularity } : {})
      }
    }
  }
  return { kind: 'structural', ...(order_mode !== undefined ? { order_mode } : {}), ...(sub_group !== undefined ? { sub_group } : {}) }
}
```
(The malformed-input guard at L145 still returns the bare literal — that path has no `obj`.)

In the `savedView` zod object, after `group_order`:
```ts
  ungrouped_placement: z.enum(EMPTY_PLACEMENTS).optional().catch(undefined),
  date_separator: z.enum(DATE_SEPARATORS).optional().catch(undefined)
```

- [ ] **Step 4:** `npx vitest run src/shared/views.test.ts` → PASS; `env -u ELECTRON_RUN_AS_NODE npm run typecheck` → clean.

- [ ] **Step 5: Commit**
```bash
git add src/shared/views.ts src/shared/views.test.ts
git commit -m "feat(views): structural order_mode + sub_group config, view-level ungrouped placement + date separator"
```

---

### Task 2: Pipeline — Ungrouped Placement Branching

Every ungrouped tail is hardcoded pinned-last (`group.ts:193`, `:233`); D-7 makes placement a passed-in value honored at every emit site.

**Files:**
- Modify: `Pommora/src/renderer/src/Detail/Views/pipeline/group.ts`, `resolveView.ts:28-31`
- Test: `Pommora/src/renderer/src/Detail/Views/pipeline/group.test.ts`

**Interfaces (Produces):** `resolveGroups(rows, group, schema, setTree, sorter, collapsed = [], placement: EmptyPlacement = 'bottom')`; internal helper `placeTail(groups, tail, placement)`.

- [ ] **Step 1: Failing tests** (reuse `group.test.ts`'s existing row/schema fixtures — read the file's helpers first and build inputs the same way):

```ts
describe('ungrouped placement', () => {
  it('structural: top placement leads with the loose tail', () => {
    const groups = resolveGroups(rows, { kind: 'structural' }, schema, setTree, null, [], 'top')
    expect(groups[0]).toMatchObject({ kind: 'ungrouped' })
  })
  it('property: top placement leads with the no-value band', () => {
    const groups = resolveGroups(rows, propertyGroup, schema, [], null, [], 'top')
    expect(groups[0]).toMatchObject({ kind: 'ungrouped' })
  })
  it('default stays bottom (legacy behavior)', () => {
    const groups = resolveGroups(rows, { kind: 'structural' }, schema, setTree, null)
    expect(groups[groups.length - 1]).toMatchObject({ kind: 'ungrouped' })
  })
})
```

- [ ] **Step 2:** `npx vitest run src/renderer/src/Detail/Views/pipeline/group.test.ts` → new tests FAIL.

- [ ] **Step 3: Implement.** In `group.ts`: add near `applySort`:
```ts
const placeTail = (groups: ResolvedGroup[], tail: ResolvedGroup, placement: EmptyPlacement): ResolvedGroup[] =>
  placement === 'top' ? [tail, ...groups] : [...groups, tail]
```
Thread `placement: EmptyPlacement` through `property()` and `structural()` signatures; replace both tail `groups.push({...})` blocks with `return placeTail(groups, tailGroup, placement)` construction. `flat()` unchanged (single band — placement is meaningless). `resolveGroups` gains the trailing param and passes it down. Import `EmptyPlacement` from `@shared/views`. In `resolveView.ts:29` pass `view.ungrouped_placement ?? 'bottom'`.

- [ ] **Step 4:** vitest file → PASS (including all pre-existing tests — bottom default preserves them); typecheck clean.

- [ ] **Step 5: Commit**
```bash
git add src/renderer/src/Detail/Views/pipeline/group.ts src/renderer/src/Detail/Views/pipeline/resolveView.ts src/renderer/src/Detail/Views/pipeline/group.test.ts
git commit -m "feat(pipeline): honor view-level ungrouped placement at every tail emit site"
```

---

### Task 3: Pipeline — Location-Order Gate

C-1a: under `order_mode: 'location'` the pipeline skips `orderGroups` so fs order wins; `group_order` is preserved-but-ignored.

**Files:**
- Modify: `Pommora/src/renderer/src/Detail/Views/pipeline/resolveView.ts:28-31`
- Test: `Pommora/src/renderer/src/Detail/Views/pipeline/resolveView.test.ts`

- [ ] **Step 1: Failing test** (fixtures per the file's existing style):
```ts
it('order_mode location ignores group_order (fs order wins, preserved not cleared)', () => {
  const view = { ...baseView, group: { kind: 'structural' as const, order_mode: 'location' as const }, group_order: ['setB', 'setA'] }
  const { groups } = resolveView({ rows, setTree, view, schema })
  expect(groups.map((g) => g.key)).toEqual(['setA', 'setB']) // tree order, not group_order
})
it('custom (absent) order_mode still applies group_order', () => {
  const view = { ...baseView, group: { kind: 'structural' as const }, group_order: ['setB', 'setA'] }
  const { groups } = resolveView({ rows, setTree, view, schema })
  expect(groups.map((g) => g.key)).toEqual(['setB', 'setA'])
})
```

- [ ] **Step 2:** Run the file → first test FAILS (group_order applied unconditionally).

- [ ] **Step 3: Implement** in `resolveView.ts`:
```ts
// Location order mirrors the filesystem: group_order is preserved on the view but ignored (C-1a).
const locationOrdered = view.group?.kind === 'structural' && view.group.order_mode === 'location'
const groups = orderGroups(
  resolveGroups(filtered, view.group, schema, setTree, sorter, view.collapsed_groups, view.ungrouped_placement ?? 'bottom'),
  locationOrdered ? undefined : view.group_order
)
```

- [ ] **Step 4:** vitest file → PASS; typecheck clean.

- [ ] **Step 5: Commit**
```bash
git add src/renderer/src/Detail/Views/pipeline/resolveView.ts src/renderer/src/Detail/Views/pipeline/resolveView.test.ts
git commit -m "feat(pipeline): location order mode skips group_order (fs order wins)"
```

---

### Task 4: Pipeline — Sub-Group Resolver Stage

E-4's net-new stage: sets stay top-level bands, sub-sets flatten, descendant pages bucket by `sub_group.property_id` inside each set; global bucket order via the existing `bucketOrder` machinery; per-bucket sort; composite collapse keys (D-11a); per-set no-value regions placed by the global placement (D-7).

**Files:**
- Modify: `Pommora/src/renderer/src/Detail/Views/pipeline/group.ts`; `Pommora/src/shared/types.ts` (~L352 `ResolvedGroup`)
- Test: `Pommora/src/renderer/src/Detail/Views/pipeline/group.test.ts`

**Interfaces (Produces):**
- `ResolvedGroup` gains `bucket?: string` — the RAW bucket value for sub-group bands (their `key` is the composite collapse identity `${setId}/${bucket}`; existing bands leave it unset).
- `subGroupKey(setId: string, bucket: string): string` exported from `group.ts` (= `` `${setId}/${bucket}` `` — set ids are ULIDs, never containing `/`).
- Sub-group bands: `kind: 'property'`, `key: subGroupKey(...)`, `bucket: <raw value>`; per-set no-value region: `kind: 'ungrouped'`, `key: subGroupKey(setId, UNGROUPED)`.

- [ ] **Step 1: Failing tests:**
```ts
describe('sub-grouping (structural + sub_group)', () => {
  const sub = { kind: 'structural' as const, sub_group: { property_id: 'status1', order_mode: 'configured' as const } }
  it('sets stay top bands; sub-set pages roll up and bucket by the property', () => {
    // setTree: A contains A1; rows: page in A (opt 'todo'), page in A1 (opt 'done')
    const groups = resolveGroups(rows, sub, schema, setTree, null, [], 'bottom')
    const setA = groups.find((g) => g.key === 'setA')!
    expect(setA.kind).toBe('structural-set')
    expect(setA.children!.map((c) => ({ kind: c.kind, bucket: c.bucket }))).toEqual([
      { kind: 'property', bucket: 'todo' },
      { kind: 'property', bucket: 'done' }
    ]) // schema order; sub-set A1's page rolled into setA's buckets — no setA1 band
    expect(groups.some((g) => g.key === 'setA1')).toBe(false)
  })
  it('composite keys keep collapse per-set', () => {
    const groups = resolveGroups(rows, sub, schema, setTree, null, [subGroupKey('setA', 'todo')], 'bottom')
    const setA = groups.find((g) => g.key === 'setA')!
    const setB = groups.find((g) => g.key === 'setB')!
    expect(setA.children!.find((c) => c.bucket === 'todo')!.isCollapsed).toBe(true)
    expect(setB.children!.find((c) => c.bucket === 'todo')!.isCollapsed).toBe(false)
  })
  it('manual sub-order is global; no-value pages sit per-set placed by the knob; loose root pages stay one flat tail', () => {
    const manual = { ...sub, sub_group: { ...sub.sub_group, order_mode: 'manual' as const, order: ['done', 'todo'] } }
    const groups = resolveGroups(rowsWithNoValueAndLoose, manual, schema, setTree, null, [], 'top')
    const setA = groups.find((g) => g.key === 'setA')!
    expect(setA.children![0]).toMatchObject({ kind: 'ungrouped', key: subGroupKey('setA', UNGROUPED) }) // top placement
    expect(setA.children!.filter((c) => c.kind === 'property').map((c) => c.bucket)).toEqual(['done', 'todo'])
    expect(groups[0]).toMatchObject({ kind: 'ungrouped', key: UNGROUPED }) // loose tail at top, un-bucketed
  })
  it('sorts within each sub-bucket (E-4 obligation 3)', () => {
    const groups = resolveGroups(unsortedRows, sub, schema, setTree, titleSorter, [], 'bottom')
    const bucket = groups.find((g) => g.key === 'setA')!.children![0]
    expect(bucket.items.map((r) => r.title)).toEqual(['Alpha', 'Beta'])
  })
})
```
(Build `rows`/`schema`/`setTree` fixtures with the file's existing helpers — a status property `status1` with options `todo`, `done` in schema order.)

- [ ] **Step 2:** Run the file → new tests FAIL.

- [ ] **Step 3: Implement.** In `types.ts`, add to `ResolvedGroup`:
```ts
  /** Sub-group bands only: the raw bucket value (`key` is the composite set/bucket collapse id). */
  bucket?: string
```
In `group.ts`:
```ts
export const subGroupKey = (setId: string, bucket: string): string => `${setId}/${bucket}`

/** E-4: Location + property Sub-Group — each TOP-LEVEL set stays a band, its whole subtree's pages
 *  flatten and re-bucket by the property inside it (global bucket order, per-bucket sort); loose
 *  root pages stay one un-bucketed tail. */
function structuralSubGrouped(
  rows: ViewRow[],
  setTree: SetTreeNode[],
  sub: SubGroupConfig,
  schema: PropertyDefinition[],
  sorter: Sorter | null,
  collapsed: Set<string>,
  placement: EmptyPlacement
): ResolvedGroup[] {
  const def = schema.find((d) => d.id === sub.property_id)
  const granularity = sub.date_granularity ?? 'month'
  const rootRows: ViewRow[] = []
  const subtreeIds = (node: SetTreeNode): string[] => [node.id, ...node.children.flatMap(subtreeIds)]
  const byParent = new Map<string, ViewRow[]>()
  for (const r of rows) {
    if (r.parentSetId === undefined) rootRows.push(r)
    else {
      const arr = byParent.get(r.parentSetId)
      if (arr) arr.push(r)
      else byParent.set(r.parentSetId, [r])
    }
  }
  const groups: ResolvedGroup[] = setTree.map((node) => {
    const pages = subtreeIds(node).flatMap((id) => byParent.get(id) ?? [])
    const buckets = new Map<string, ViewRow[]>()
    const noValue: ViewRow[] = []
    for (const r of pages) {
      const key = bucketKey(r, sub.property_id, schema, granularity)
      if (key === null) noValue.push(r)
      else {
        const arr = buckets.get(key)
        if (arr) arr.push(r)
        else buckets.set(key, [r])
      }
    }
    const order = bucketOrder({ order_mode: sub.order_mode, order: sub.order } as PropertyGroup, def, new Set(buckets.keys()))
    let children: ResolvedGroup[] = order.flatMap((b) => {
      const items = buckets.get(b)
      if (!items) return []
      const key = subGroupKey(node.id, b)
      return [{ key, bucket: b, kind: 'property' as const, items: applySort(items, sorter), isCollapsed: collapsed.has(key) }]
    })
    if (noValue.length > 0) {
      const key = subGroupKey(node.id, UNGROUPED)
      children = placeTail(children, { key, kind: 'ungrouped', items: applySort(noValue, sorter), isCollapsed: collapsed.has(key) }, placement)
    }
    return {
      key: node.id,
      kind: 'structural-set' as const,
      items: [],
      ...(children.length > 0 ? { children } : {}),
      isCollapsed: collapsed.has(node.id)
    }
  })
  if (rootRows.length === 0) return groups
  return placeTail(groups, { key: UNGROUPED, kind: 'ungrouped', items: applySort(rootRows, sorter), isCollapsed: collapsed.has(UNGROUPED) }, placement)
}
```
Note `bucketOrder`'s first param only reads `order_mode`/`order` — loosen its param to `Pick<PropertyGroup, 'order_mode' | 'order'>` (no cast), and **add `export` to it** — Task 9's Custom list imports it (DRY; no replication in the pane).

Route it in `resolveGroups`'s `default:` (structural) arm:
```ts
    default: {
      const sub = group?.kind === 'structural' ? group.sub_group : undefined
      const t = sub ? declaredType(sub.property_id, schema) : undefined
      if (sub && t !== undefined && GROUPABLE.has(t))
        return structuralSubGrouped(rows, setTree, sub, schema, sorter, collapsedSet, placement)
      return structural(rows, setTree, sorter, collapsedSet, placement)
    }
```
(An unmappable sub-group property falls back to plain structural — the E-3 rule one level down.)

- [ ] **Step 4:** `npx vitest run src/renderer/src/Detail/Views/pipeline/` → all PASS; typecheck clean.

- [ ] **Step 5: Commit**
```bash
git add src/shared/types.ts src/renderer/src/Detail/Views/pipeline/group.ts src/renderer/src/Detail/Views/pipeline/group.test.ts
git commit -m "feat(pipeline): sub-group resolver — property buckets inside set bands, composite collapse keys"
```

---

### Task 5: Table Render — Sub-Group Glyphs + Formatted Date Headings + Scoped "+"

**Files:**
- Modify: `Pommora/src/renderer/src/Detail/Views/PropertyEditing/formatValue.ts`; `Pommora/src/renderer/src/Detail/Views/Table/GroupHeader.tsx`
- Test: Create `Pommora/src/renderer/src/Detail/Views/PropertyEditing/formatBucketLabel.test.ts`

**Interfaces (Produces):**
```ts
export function formatBucketLabel(key: string, granularity: DateGranularity, dateFormat: DateFormat, separator: DateSeparator): string
```

- [ ] **Step 1: Failing tests** (new file):
```ts
import { describe, expect, it } from 'vitest'
import { formatBucketLabel } from './formatValue'

describe('formatBucketLabel', () => {
  it('worded formats: month bucket reads written', () => {
    expect(formatBucketLabel('2026-07', 'month', 'full', 'dash')).toBe('July 2026')
  })
  it('numeric formats: month bucket uses the separator', () => {
    expect(formatBucketLabel('2026-07', 'month', 'monthDayYear', 'dash')).toBe('07-2026')
    expect(formatBucketLabel('2026-07', 'month', 'monthDayYear', 'slash')).toBe('07/2026')
  })
  it('day buckets ride formatDate; dash swaps numeric separators', () => {
    expect(formatBucketLabel('2026-07-09', 'day', 'monthDayYear', 'dash')).toBe('07-09-2026')
    expect(formatBucketLabel('2026-07-09', 'day', 'full', 'dash')).toBe('July 9th, 2026')
  })
  it('year + week buckets', () => {
    expect(formatBucketLabel('2026', 'year', 'full', 'dash')).toBe('2026')
    expect(formatBucketLabel('2026-W28', 'week', 'full', 'dash')).toBe('Week 28, 2026')
    expect(formatBucketLabel('2026-W28', 'week', 'monthDayYear', 'dash')).toBe('W28-2026')
  })
  it('unparseable keys fall back raw', () => {
    expect(formatBucketLabel('junk', 'month', 'full', 'dash')).toBe('junk')
  })
})
```

- [ ] **Step 2:** Run the new file → FAIL (`formatBucketLabel` not exported).

- [ ] **Step 3: Implement** in `formatValue.ts` (below `formatDate`):
```ts
const NUMERIC_FORMATS = new Set<DateFormat>(['dayMonthYear', 'monthDayYear'])

/** A date group-heading label from its stable bucket key (D-8/G-3): worded formats read written
 *  ("July 2026"); numeric formats read numeric with the view's separator ("07-2026"). */
export function formatBucketLabel(key: string, granularity: DateGranularity, dateFormat: DateFormat, separator: DateSeparator): string {
  const numeric = NUMERIC_FORMATS.has(dateFormat)
  const sep = separator === 'slash' ? '/' : '-'
  switch (granularity) {
    case 'year':
      return key
    case 'week': {
      const m = /^(\d{4})-W(\d{2})$/.exec(key)
      if (!m) return key
      return numeric ? `W${m[2]}${sep}${m[1]}` : `Week ${Number(m[2])}, ${m[1]}`
    }
    case 'month': {
      const m = /^(\d{4})-(\d{2})$/.exec(key)
      if (!m) return key
      if (numeric) return dateFormat === 'dayMonthYear' ? `${m[2]}${sep}${m[1]}` : `${m[2]}${sep}${m[1]}`
      const month = new Date(`${key}-01T00:00:00`).toLocaleDateString('en-US', { month: 'long' })
      return `${month} ${m[1]}`
    }
    case 'day': {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) return key
      const out = formatDate(key, dateFormat, 'none')
      return numeric && separator === 'dash' ? out.replaceAll('/', '-') : out
    }
  }
}
```
(Both numeric families render month buckets `MM<sep>YYYY` — there's no day component to transpose.)

Then in `GroupHeader.tsx`:
- Resolve the property id + raw value for BOTH property-band homes (replace L39–40):
```ts
  const propId =
    view.group?.kind === 'property'
      ? view.group.property_id
      : view.group?.kind === 'structural'
        ? view.group.sub_group?.property_id
        : undefined
  if (!propId) return <span className="group-name">{group.key}</span>
  const value = group.bucket ?? group.key
```
Use `value` (not `group.key`) in the `findOption(propId, value, ...)` call, the checkbox `value === 'true'` check, and the datetime label.
- Datetime branch renders the formatted label:
```ts
    case 'datetime': {
      const def = ctx.schema.find((d) => d.id === propId)
      const icon = asRenderableIcon(def?.icon)
      const style = view.column_styles?.[propId]
      const granularity =
        (view.group?.kind === 'property' ? view.group.date_granularity : view.group?.sub_group?.date_granularity) ?? 'month'
      const label = formatBucketLabel(value, granularity, style?.date_format ?? 'full', view.date_separator ?? 'dash')
      return (
        <span className="group-name">
          {icon ? <Icon name={icon} size={13} /> : null}
          {label}
        </span>
      )
    }
```
- Scope the "+" (D-5): render the `group-add` button only for structural-set bands — wrap the existing button in `{group.kind === 'structural-set' ? (<button …/>) : null}`. (Property bands — top-level or sub-group — lose it; it was inert anyway.)

- [ ] **Step 4:** `npx vitest run src/renderer/src/Detail/Views` → PASS (fix any GroupHeader-consuming render tests that asserted the raw key); typecheck clean.

- [ ] **Step 5: Commit**
```bash
git add src/renderer/src/Detail/Views/PropertyEditing/formatValue.ts src/renderer/src/Detail/Views/PropertyEditing/formatBucketLabel.test.ts src/renderer/src/Detail/Views/Table/GroupHeader.tsx
git commit -m "feat(table): formatted date group headings, sub-group band glyphs, location-only +"
```

---

### Task 6: Table Writes — Drop-Router Mode Branch + Sub-Order Writes

C-1c: same-parent structural reorder gates on `order_mode` (Location → `reorderChildren` fs write; Custom → `group_order` as today; cross-tree reparent ALWAYS writes `group_order` after `moveSet`, every mode). F-1: sub-group bucket drag (manual mode only) writes the global `sub_group.order`.

**Files:**
- Modify: `Pommora/src/renderer/src/Detail/Views/Table/TableView.tsx` (`onBandDrop`, ~L335–370)
- Test: `Pommora/src/renderer/src/Detail/Views/Table/bandCommits.test.tsx`

- [ ] **Step 1: Failing tests** — follow the file's existing harness (it mounts TableView with a stubbed `window.nexus` and asserts on `views.save` / `mutate` payloads):
```ts
it('location mode: same-parent band reorder writes reorderChildren, not group_order', async () => {
  // view.group = { kind: 'structural', order_mode: 'location' }; drag setB before setA (both root)
  // assert mutate called with { op: 'reorderChildren', parentPath: source.path, key: 'set_order', order: ['setB', 'setA'] }
  // assert views.save NOT called with a group_order change
})
it('location mode: cross-tree reparent still writes group_order after moveSet (slot preservation)', async () => {
  // existing reparent fixture + order_mode: 'location' — both writes still fire
})
it('sub-group bucket drag in manual mode writes global sub_group.order', async () => {
  // view.group = { kind: 'structural', sub_group: { property_id, order_mode: 'manual' } }
  // drag bucket band `${setA}/done` before `${setA}/todo`
  // assert views.save payload group.sub_group.order = ['done', 'todo']
})
it('CROSS-SET bucket drag (arrives as reparent) still writes the global sub-order', async () => {
  // drag `${setA}/done` into setB's region before `${setB}/todo` → drop kind 'reparent'
  // assert views.save payload group.sub_group.order = ['done', 'todo'] — no moveSet fires
})
it('sub-group bucket drag outside manual mode is inert', async () => {
  // order_mode: 'configured' — no save fires
})
```

- [ ] **Step 2:** Run the file → new tests FAIL.

- [ ] **Step 3: Implement** in `onBandDrop`:

Property-band branch (L335–345) extends to the sub-group home:
```ts
    if (dragged.kind === 'property') {
      if (liveView.group?.kind === 'property') {
        if (drop.kind !== 'reorder') return
        /* existing top-level body (present/order/commitBand) unchanged — only its guard moved up */
      }
      if (liveView.group?.kind === 'structural' && liveView.group.sub_group) {
        // F-1: global sub-order, manual mode only — dragging one set's bucket reorders it everywhere.
        // A CROSS-SET bucket drag arrives as kind 'reparent' (bandDnd routes by impliedParentId —
        // bandDnd.tsx:180-182), and it's STILL a global reorder: resolve the target position from
        // drop.beforeId's bucket value (null = append), ignore targetParentId entirely.
        if (liveView.group.sub_group.order_mode !== 'manual') return
        const bucketOf = (key: string): string | undefined => {
          const find = (gs: ResolvedGroup[]): string | undefined => {
            for (const g of gs) {
              if (g.key === key) return g.bucket
              const hit = g.children ? find(g.children) : undefined
              if (hit !== undefined) return hit
            }
            return undefined
          }
          return find(groups)
        }
        const draggedBucket = bucketOf(draggedId)
        const beforeBucket = drop.beforeId === null ? null : (bucketOf(drop.beforeId) ?? null)
        if (draggedBucket === undefined) return
        const present = [...new Set(groups.flatMap((g) => (g.children ?? []).flatMap((c) => (c.bucket !== undefined ? [c.bucket] : []))))]
        const sub_group = { ...liveView.group.sub_group, order: propertyOrderAfterDrop(present, draggedBucket, beforeBucket) }
        commitBand({ group: { ...liveView.group, sub_group } })
      }
      return
    }
```
(`propertyOrderAfterDrop` already takes `(present, draggedId, beforeId)` — here fed bucket VALUES; a cross-set drop's beforeId resolves to that set's bucket value, which is exactly the global-reorder semantic.)

Structural reorder branch (L347–349) gates on mode:
```ts
    if (drop.kind === 'reorder') {
      if (liveView.group?.kind === 'structural' && liveView.group.order_mode === 'location') {
        // C-1c: Location mode — the reorder IS the filesystem write; group_order stays untouched.
        const parentId = dragged.parentId
        const parentPath = parentId === null ? source.path : setPaths.get(parentId)
        const siblingIds = parentId === null ? setTree.map((n) => n.id) : (childIdsOf(setTree, parentId) ?? [])
        if (!parentPath) return
        const next = nextOrder(siblingIds, draggedId, drop.beforeId)
        void mutate({ op: 'reorderChildren', parentPath, key: 'set_order', order: next })
        return
      }
      commitBand({ group_order })
      return
    }
```
Notes for the implementer: `childIdsOf` already exists below (L351–358) — hoist it above the branch; `nextOrder` is the sidebar-model reorder helper `structuralOrderAfterDrop` already uses (`bandDndModel.ts` imports it — re-export or import the same source). `dragged` is the Band for `draggedId` (from the band index — mirror how the reparent branch resolves paths). Verify against `src/main/mutate.ts`'s `reorderChildren` case that `key: 'set_order'` is correct for sets under a collection AND under a set (the `ChildOrderKey` union) — if a set's children ride a different key, branch on `parentId === null`.

The reparent branch (L366–369) is UNTOUCHED — it writes `group_order` in every mode by design (C-1c slot preservation).

- [ ] **Step 4: The F-2 row drop — net-new dual-mutation, scoped honestly.** The cross-group row-drop orchestration is INLINE in `TableView.tsx` (`reassignRow` ~L980 + `reorderTo` ~L999; `groupKeyToValue` from `reassign.ts` is a pure value mapper — REUSED, not extended). **Blast radius first:** the `groupPropId` / `groupPropType` / `canReassign` cluster (`TableView.tsx:259-261`) is property-mode-only — it must gain the sub-group branch (`liveView.group.kind === 'structural' && liveView.group.sub_group` → resolve from `sub_group.property_id`), or `reassignRow` early-returns (`L982`) and the whole F-2 reassignment half silently no-ops. `reassignRow` also needs the destination BUCKET value (from the composite key), not the composite key itself. No cross-set row move exists today, so this is new branching in that handler for the sub-group case: resolve the target bucket band's parent SET id from its composite key's ResolvedGroup ancestry, then (a) different set + different bucket → `movePage` into that set's path AND `setProperty` via `groupKeyToValue`; (b) same set, different bucket → `setProperty` alone (existing semantic); (c) different set, same bucket → `movePage` alone. Write the three cases as TableView-level tests in `bandCommits.test.tsx`'s harness style (it asserts mutate payloads; `reassign.test.ts` stays a pure mapper test), run failing, implement.

- [ ] **Step 5:** `npx vitest run src/renderer/src/Detail/Views/Table/` then the full suite → PASS; typecheck clean.

- [ ] **Step 6: Commit**
```bash
git add src/renderer/src/Detail/Views/Table/TableView.tsx src/renderer/src/Detail/Views/Table/bandCommits.test.tsx src/renderer/src/Detail/Views/Table/reassign.test.ts
git commit -m "feat(table): location-mode fs reorder, global sub-order drag, cross-set bucket row drop"
```

---

### Task 7: Footing Value-Pick IPC

A generic native value-pick menu in the `openInMenu` family (G-4): renderer passes labeled options + the current one; main pops a radio menu; returns the pick or null.

**Files:**
- Create: `Pommora/src/main/valueMenu.ts`
- Modify: `Pommora/src/main/index.ts` (register beside `open-in-menu`; see `popOpenInMenu` import at L71); `Pommora/src/preload/index.ts` (beside `openInMenu`, L93)

**Interfaces (Produces):** `window.nexus.valueMenu(options: string[], current: string): Promise<string | null>`

- [ ] **Step 1: Implement** (main-process native-menu code — no unit test; the pattern is `openInMenu`'s, verified by the existing handler):

`src/main/valueMenu.ts` — reuse `popReturningMenu` (`src/main/returningMenu.ts`, the generalized pick-resolving popup `openInMenu` already rides — open it and follow its option shape exactly; don't hand-roll a second popup/promise dance):
```ts
// Generic native value-pick menu (Grouping pane footings — G-4): radio list over popReturningMenu,
// resolving the picked label or null on dismiss. One handler for every footing.
import type { BrowserWindow } from 'electron'
import { popReturningMenu } from './returningMenu'

export function popValueMenu(win: BrowserWindow, options: string[], current: string): Promise<string | null> {
  return popReturningMenu<string>(win, (pick) =>
    options.map((label) => ({ label, type: 'radio' as const, checked: label === current, click: pick(label) }))
  )
}
```
(`popReturningMenu<A>(win, buildItems)` — `returningMenu.ts:9` — takes a CALLBACK receiving a `pick` factory; `openInMenu.ts:9-12` is the live precedent.)
In `src/main/index.ts`, next to the `open-in-menu` registration (grep `popOpenInMenu` for the exact site) add:
```ts
ipcMain.handle('value-menu', (e, options: string[], current: string) => {
  const win = BrowserWindow.fromWebContents(e.sender)
  return win ? popValueMenu(win, options, current) : null
})
```
In `src/preload/index.ts` beside `openInMenu`:
```ts
  valueMenu: (options: string[], current: string): Promise<string | null> => ipcRenderer.invoke('value-menu', options, current),
```

- [ ] **Step 2:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` → clean; `npx vitest run` → green (no regressions).

- [ ] **Step 3: Commit**
```bash
git add src/main/valueMenu.ts src/main/index.ts src/preload/index.ts
git commit -m "feat(ipc): generic native value-pick menu for pane footings"
```
Reminder: main/preload changes need a full dev-process restart to test live — ⌘R won't pick them up.

---

### Task 8: GroupingPane — Rows + Group By Disclosure + Pickers + Both Doors

The pane skeleton: header, the value-row stack (B-1/C-7/C-8), the Group By vertical disclosure (G-1), dropdown pickers for Order / Date By / Sub-Group / Sub-Order (D-6/D-10), wired into both doors. The middle region + footings land in Tasks 9–10 (render placeholders `null` here).

**Files:**
- Create: `Pommora/src/renderer/src/Components/Detail/GroupingPane.tsx`
- Modify: `Pommora/src/renderer/src/Components/Detail/SettingsPane.tsx:167-169` (route `group`); `Pommora/src/renderer/src/Components/Detail/ViewSettings.tsx` (route its Group leaf, ~L134)

**Interfaces:**
- Consumes: `pickView` (SettingsPane already imports it), `saveViewAdopting(containerPath, kind, view)` from `Detail/Views/viewMint`, `MenuItem/MenuSeparator/MenuPaneTopRow` + `detail`/`side`/`flushTrailing` classes, `Reveal`, `PickerMenu`/`PickerOption`, `GROUPABLE`-equivalent filtering via `declaredType`.
- Produces: `GroupingPane({ source, view, schema, onBack }): JSX` — `source: CollectionNode | SetNode`.

- [ ] **Step 1: Component core** (complete structure; visual classes follow SettingsPane's leaf idiom):
```tsx
import { useRef, useState } from 'react'
import type { CollectionNode, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import type { DateGranularity, GroupConfig, SavedView, SubGroupConfig } from '@shared/views'
import { Icon, asRenderableIcon } from '@renderer/design-system/symbols'
import { MenuItem, MenuSeparator, MenuPaneTopRow } from '../../design-system/components/menu'
import { detail as detailText, flushTrailing, side } from '../../design-system/components/menu/menu.css'
import { Reveal } from '../../design-system/components/Reveal'
import { PickerMenu, PickerOption } from '../../design-system/components/PickerMenu/PickerMenu'
import { saveViewAdopting } from '../../Detail/Views/viewMint'
import { declaredType } from '../../Detail/Views/pipeline/value'
import { useSession } from '../../store'

const GROUPABLE_PANE = new Set(['select', 'status', 'datetime']) // B-2: checkbox never offered
const GRANULARITY_LABELS: Record<DateGranularity, string> = { day: 'Day', week: 'Week', month: 'Month', year: 'Year' }

export function GroupingPane({ source, view, schema, label, onBack }: {
  source: CollectionNode | SetNode
  view: SavedView
  schema: PropertyDefinition[]
  /** The back-destination breadcrumb — 'Settings' from SettingsPane, 'Views' from the ViewSettings
   *  full door (matches VisibilityList's label/current pattern). */
  label: string
  onBack: () => void
}): React.JSX.Element {
  const load = useSession((st) => st.load)
  const [groupByOpen, setGroupByOpen] = useState(false)
  // The ONE view writer, ViewSettings.tsx:83's exact idiom — source NODE, merged view, refetch positional.
  const save = (patch: Partial<SavedView>): void => void saveViewAdopting(source, { ...view, ...patch }, load)
  const saveGroup = (group: GroupConfig): void => save({ group })

  const group = view.group ?? { kind: 'structural' as const }
  const structural = group.kind === 'structural' || group.kind === 'flat'
  const groupable = schema.filter((d) => GROUPABLE_PANE.has(declaredType(d.id, schema) ?? ''))
  const activeDef = group.kind === 'property' ? schema.find((d) => d.id === group.property_id) : undefined
  const groupByLabel = structural ? 'Location' : (activeDef?.name ?? 'Location')

  const pickGroupBy = (target: 'location' | PropertyDefinition): void => {
    setGroupByOpen(false)
    if (target === 'location') {
      // E-3: preserved fields (order_mode / sub_group) restore on the flip back.
      saveGroup(group.kind === 'structural' ? group : { kind: 'structural' })
      return
    }
    saveGroup({ kind: 'property', property_id: target.id, order_mode: 'configured', empty_placement: view.ungrouped_placement ?? 'bottom', hide_empty_groups: false })
  }

  return (
    <>
      <MenuPaneTopRow label={label} current="Grouping" onBack={onBack} />
      <ValueRow tier="primary" icon="layers" label="Group By" value={groupByLabel} onClick={() => setGroupByOpen((o) => !o)} />
      <Reveal open={groupByOpen}>
        <MenuItem leading={<Icon name="folder" size={13} />} onClick={() => pickGroupBy('location')}
          trailing={structural ? <Icon name="check" size={12} /> : undefined}>Location</MenuItem>
        {groupable.map((d) => (
          <MenuItem key={d.id} leading={<Icon name={asRenderableIcon(d.icon) ?? 'tag'} size={13} />}
            trailing={group.kind === 'property' && group.property_id === d.id ? <Icon name="check" size={12} /> : undefined}
            onClick={() => pickGroupBy(d)}>{d.name}</MenuItem>
        ))}
      </Reveal>
      {!groupByOpen && (
        <>
          {group.kind === 'property' && declaredType(group.property_id, schema) === 'datetime' && (
            <DateByRow value={group.date_granularity ?? 'month'} onPick={(g) => saveGroup({ ...group, date_granularity: g })} />
          )}
          <OrderRow group={group} view={view} onSave={saveGroup} onSaveView={save} />
          {group.kind === 'structural' && (
            <>
              <SubGroupRow group={group} groupable={groupable} schema={schema} onSave={saveGroup} />
              {group.sub_group && declaredType(group.sub_group.property_id, schema) === 'datetime' && (
                <DateByRow value={group.sub_group.date_granularity ?? 'month'}
                  onPick={(g) => saveGroup({ ...group, sub_group: { ...group.sub_group!, date_granularity: g } })} />
              )}
              {group.sub_group && <SubOrderRow group={group} schema={schema} onSave={saveGroup} />}
            </>
          )}
          <MenuSeparator flush />
          {/* Task 9: middle region */}
          {/* Task 10: footings */}
        </>
      )}
    </>
  )
}
```
Supporting pieces in the same file — write these fully:
- `ValueRow({ tier, icon, label, value, onClick, pickerRef? })` — a `MenuItem` with `className={flushTrailing}`, trailing `<span className={side}><span className={detailText}>{value}</span><Icon name="chevrons-up-down" size={12}/></span>`. `tier: 'primary' | 'sub'` — `sub` renders the label through a new pair of classes added to a small `groupingPane.css.ts` (label-secondary + Control-Emphasized + a reduced top-margin knob, all via tokens; C-8's "slightly reduced padding" is the tunable knob — name it `--grouping-suborder-gap`).
- `OrderRow` — a `ValueRow tier="sub"` whose click opens a self-managed `PickerMenu` (state + `triggerRef` on the row, per the DatetimeCellPicker idiom). Options by kind (D-10): structural → Custom/Location (writes `order_mode: 'custom' | 'location'`); property select/status → Default/Reversed/Custom (`order_mode: 'configured' | 'reversed' | 'manual'`); property datetime → Ascending/Descending (`configured` / `reversed`). Labels ↔ mode maps live as consts.
- `SubGroupRow` — `ValueRow tier="primary" icon="layers" label="Sub-Group"`, PickerMenu of Location + `groupable` (C-4: empty schema ⇒ Location alone). Picking Location deletes `sub_group` (`const { sub_group: _drop, ...rest } = group; onSave(rest)`); picking a property writes `sub_group: { property_id: d.id, order_mode: 'configured' }`.
- `SubOrderRow` — the sub-group's `ValueRow tier="sub"` Order (same option logic keyed off the sub-group property's type, writing `sub_group.order_mode`).
- `DateByRow` — `ValueRow tier="primary"` labeled `Date By`, PickerMenu over `GRANULARITY_LABELS`.

- [ ] **Step 2: Wire both doors.** SettingsPane's Group entry already routes to its `blankLeaf` fall-through (`SettingsPane.tsx:150-169`) — insert a branch before it (keep filter/sort blank):
```tsx
    ) : detailId === 'group' ? (
      <GroupingPane source={node} view={pickView(node, activeViewId, schema)} schema={schema} label="Settings" onBack={back} />
    ) : (
      blankLeaf
    )
```
`ViewSettings.tsx` — the full-door leaf lives in `leafPane` (`ViewSettings.tsx:122-136`), where `group` currently falls to the bare `MenuPaneTopRow`. Insert before that fall-through:
```tsx
    ) : leaf === 'group' ? (
      <GroupingPane source={source} view={view} schema={schema} label="Views" onBack={() => setLeaf(null)} />
    ) : leaf ? (
```
(ViewSettings already holds `source`/`view`/`schema` in scope; the flat door reaches Grouping through SettingsPane's own Group entry, not through ViewSettings — the leaf rows are full-door-only by design.)

- [ ] **Step 3: Render test** — create `Pommora/src/renderer/src/Components/Detail/GroupingPane.test.tsx` on the project's `createRoot`/`act` harness (copy a mount fixture from an existing pane test): mount with a structural view → assert "Group By" + "Location" + "Order" render and "Date By" doesn't; mount with a datetime property group → assert "Date By" renders with "Month".

- [ ] **Step 4:** vitest + typecheck → green.

- [ ] **Step 5: Commit**
```bash
git add src/renderer/src/Components/Detail/GroupingPane.tsx src/renderer/src/Components/Detail/GroupingPane.test.tsx src/renderer/src/Components/Detail/groupingPane.css.ts src/renderer/src/Components/Detail/SettingsPane.tsx src/renderer/src/Components/Detail/ViewSettings.tsx
git commit -m "feat(pane): GroupingPane rows + Group By disclosure behind both doors"
```

---

### Task 9: GroupingPane — Middle Region (Hierarchy · Preview · Custom List)

The scrollable body between the dividers (G-2): location hierarchy with drag (F-4), the read-only property preview (D-9), and the Custom flattened chip list (D-2).

**Files:**
- Modify: `Pommora/src/renderer/src/Components/Detail/GroupingPane.tsx` (+ `groupingPane.css.ts`)
- Test: extend `GroupingPane.test.tsx`

**Interfaces (Consumes):** the bare `overflow-eclipse-y` CSS class applied directly to the pane's own scroll container (the Icon Picker precedent — the `OverflowScroll` COMPONENT is horizontal-only and doesn't fit here), the band-engine drag model from `bandDndModel.ts` (see body 1 — `paneDnd` is the wrong engine for hierarchy), `PaneDnd`/`RowShell` ONLY for the flat Custom chip list (body 3 — a flat single-region list fits it), `Chip`/`chipColorFor`/`chipShapeForType`, set walking over `source.sets` directly (ids + names + icons), `footingLabel` for the muted group headings, `propertyOrderAfterDrop`-style reorder math via the sidebar `nextOrder` helper.

Three bodies, switched by config:

1. **Location hierarchy** (`group.kind === 'structural'`): walk `source.sets` recursively → rows of folder icon + name, depth-indented; sub-sets get a local expand/collapse chevron (pane-local `useState<Set<string>>`, not persisted). When `sub_group` is set, render the FLAT set list (F-3: top-level sets only, no children). **Drag engine: `paneDnd` does NOT fit** — its model is a fixed two-region assigned/all vocabulary with no `parentId`/nest concept. The hierarchy drag is NET-NEW slot logic built on the BAND engine's model (`bandDndModel.ts` — `Band`/`impliedParentId`/`nestInto` already express parent-linked rows + reparent): either mount a pane-hosted `BandDnd`-style gesture over the row list, or write a parentId-aware `paneSlot` sibling — name whichever in the task commit, but do not wire `PaneDnd`/`RowShell` for this list. Semantics: a between-rows drop with the same implied parent = sibling reorder → Custom mode writes `group_order` (merge over the full tree exactly like `structuralOrderAfterDrop`), Location mode fires `mutate({ op: 'reorderChildren', … })` (C-1/F-4); a drop ONTO a set row = reparent → always `mutate({ op: 'moveSet', … })` + the `group_order` slot write (mirror Task 6's table semantics; hoist `childIdsOf`/order math into `bandDndModel.ts` exports rather than duplicating).
2. **Read-only preview** (`group.kind === 'property'`, order_mode ≠ manual): for status — its `status_groups` as muted headings (`footingLabel` class) with each group's option chips beneath (`Chip` with `chipShapeForType`); for select — one flat chip run; for datetime — nothing (no finite option list). Reversed renders the reversed sequence. Zero handlers (D-9).
3. **Custom list** (`order_mode === 'manual'`): "Options" muted heading, then one draggable chip row per option in `bucketOrder`-derived order — import the real `bucketOrder` from `group.ts` (Task 4 exports it; never replicate). Drop writes `group.order` (top-level) — the sub-group's custom list is NOT in the pane (its reorder surface is the table bands, F-1).

Wrap all three in the scroll body with the vertical eclipse fade; cap rides the existing MenuScrollFrame/height conventions (the pinned rows above and footings below never scroll).

- [ ] **Step 1: Failing tests:** structural view → set names render nested; with `sub_group` → flat list; status/configured → group headings + chips, no drag handles; status/manual → flat "Options" chips.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement per above. **Step 4:** vitest + typecheck green.
- [ ] **Step 5: Commit**
```bash
git add src/renderer/src/Components/Detail/GroupingPane.tsx src/renderer/src/Components/Detail/groupingPane.css.ts src/renderer/src/Components/Detail/GroupingPane.test.tsx src/renderer/src/Detail/Views/Table/bandDndModel.ts
git commit -m "feat(pane): grouping middle region — hierarchy, preview, custom order list"
```

---

### Task 10: GroupingPane — Footings

C-9/G-5/G-6: `Ungrouped: Top/Bottom` (always) and `Separation: Dash/Slash` (datetime grouping under a numeric format) as native value-pick footings; `Hide Empty Groups` (property grouping only) as a checkbox-style toggle.

**Files:**
- Modify: `Pommora/src/renderer/src/Components/Detail/GroupingPane.tsx`
- Test: extend `GroupingPane.test.tsx`

- [ ] **Step 1: Implement** below the middle region:
```tsx
function FootingPick({ label, value, options, onPick }: {
  label: string; value: string; options: string[]; onPick: (v: string) => void
}): React.JSX.Element {
  return (
    <MenuItem className={flushTrailing}
      trailing={<span className={side}><span className={detailText}>{value}</span><Icon name="chevrons-up-down" size={11} /></span>}
      onClick={() => void window.nexus.valueMenu(options, value).then((v) => { if (v) onPick(v) })}>
      <span className={footingLabel}>{label}</span>
    </MenuItem>
  )
}
```
Footer block (after a `MenuSeparator flush`):
- `<FootingPick label="Ungrouped" value={cap(view.ungrouped_placement ?? 'bottom')} options={['Top','Bottom']} onPick={(v) => save({ ungrouped_placement: v.toLowerCase() as EmptyPlacement })} />`
- When the active grouping property (top-level, D-8) is datetime AND its `column_styles` date format is numeric (`dayMonthYear`/`monthDayYear`): `<FootingPick label="Separation" value={…Dash/Slash…} onPick={(v) => save({ date_separator: … })} />`
- When `group.kind === 'property'`: a checkbox-toggle row (G-5 — the Figma treatment; reuse the chip-box check idiom or the `Switch`-free `chipBox` + `check` glyph the table's checkbox look uses) flipping `hide_empty_groups` via `saveGroup({ ...group, hide_empty_groups: !group.hide_empty_groups })`, label in `footingLabel`.

- [ ] **Step 2: Tests:** structural view shows Ungrouped and NOT Separation/Hide Empty Groups; property(status) shows Hide Empty Groups; datetime + `monthDayYear` style shows Separation. Stub `window.nexus.valueMenu` to resolve `'Top'` and assert the `views.save` payload carries `ungrouped_placement: 'top'`.
- [ ] **Step 3:** vitest + typecheck green.
- [ ] **Step 4: Commit**
```bash
git add src/renderer/src/Components/Detail/GroupingPane.tsx src/renderer/src/Components/Detail/GroupingPane.test.tsx
git commit -m "feat(pane): grouping footings — ungrouped placement, separation, hide empty groups"
```

---

### Task 11: Docs Reconciliation

Per H-1..H-3 — written as durable truth, never as changelog.

**Files:**
- Modify: `.claude/Features/Views.md` (blank-leafs line + Pending entry + the pipeline Group paragraph), `.claude/Features/TableView.md` (Groups section, band-drag fs-conditionality, ungrouped placement, Prospects "+"), `.claude/History.md` (one locked-decisions entry)

- [ ] **Step 1:** `Views.md` — Group leaves the "blank leafs" list (Filter/Sort stay); the pipeline **Group** bullet gains: sub-grouping (location + property buckets per set band, sub-sets flatten, global bucket order), the structural order mode (Custom = view-owned / Location = fs-mirroring), and the view-level ungrouped placement. The Pending "View-Settings Editing Panes" entry drops Group.
- [ ] **Step 2:** `TableView.md` — the **Groups** paragraph gains sub-group bands + composite collapse keys + placement; the **Band drag** paragraph's "only a cross-tree drop touches the filesystem" becomes conditional on the order mode (Location: same-parent reorders write the filesystem too); Prospects gains the disabled off-location "+" entry (D-5).
- [ ] **Step 3:** `History.md` — one dated entry: pane shipped, the three pipeline mechanisms, the model extension, labels ratified.
- [ ] **Step 4: Commit**
```bash
git add ".claude/Features/Views.md" ".claude/Features/TableView.md" ".claude/History.md"
git commit -m "docs: grouping pane — Views/TableView reconciliation + History entry"
```

---

### Task 12: Final Gates + Live UIX Pass

- [ ] **Step 1:** Full gates: `env -u ELECTRON_RUN_AS_NODE npm run typecheck` · `npx vitest run` · `npm run build` (run in background) — all green.
- [ ] **Step 2:** Launch dev (`env -u ELECTRON_RUN_AS_NODE npm run dev`, background) and CDP-screenshot the pane in each state (location, location+sub-group, status default/custom, datetime + footings) — **open + Esc only against the real Nexus; create a throwaway Collection for any interaction that writes.** Fix what's visibly off; the mandatory post-functional UIX review runs with Nathan before closeout — functional-green ≠ done.
- [ ] **Step 3:** Do NOT merge to main — present the branch + screenshots to Nathan.

---

## Self-Review Notes (spec → task trace)

A-1/A-2 → T8 · B-1..B-4 → T8 · C-1/C-1a..c → T3+T6+T9 · C-2/C-3 → T9+T10 · C-4/C-11 → T4+T8 · C-7/C-8 → T8 · C-9 → T7+T10 · C-10 → T4 · D-1..D-3, D-9, D-10 → T8+T9 · D-4/D-5/D-8 → T5 · D-6 → T8 · D-7 → T2+T10 · D-11/D-11a → T4 (keys) + existing collapse UI · E-1/E-2 → T1 · E-3 → T8 (pickGroupBy preservation) + T4 (fallback) · E-4 → T4 · F-1 → T6 Steps 1–3 · F-2 → T6 Step 4 · F-3/F-4 → T9 · G-1..G-6 → T7..T10 · H-1..H-3 → T11.
