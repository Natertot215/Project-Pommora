# View Filtering (FilterPane) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the FilterPane — the last blank ViewSettings/SettingsPane leaf — authoring the view's `filter` as flat And/Or rule rows under a Matches (All/Any/None) header, over an extended evaluator (new operators, Title, Location, multi-operand `values[]`, lossless disable).

**Architecture:** Three layers, built bottom-up: (1) the shared data model (`views.ts` codec: `values[]` field + `match: 'none'`), (2) the pure evaluator (`pipeline/filter.ts`: op registry + per-type branches) and the pure pane↔tree serializer (`filterModel.ts`), (3) the pane itself on the GroupingPane/SortingPane chassis, hosted behind both doors. Every write goes through `saveViewAdopting`; the pipeline already consumes `view.filter` first in `resolveView`.

**Tech Stack:** React 19 + TypeScript, zod codecs in `src/shared`, vanilla-extract CSS, Vitest. Spec: `.claude/Planning/7-9 - View Filtering — Decision Log.md` (review-certified, 3 rounds).

## Global Constraints

- Gates after every task: `set -o pipefail; env -u ELECTRON_RUN_AS_NODE npm run typecheck && npx vitest run` (full build `env -u ELECTRON_RUN_AS_NODE npm run build` at phase ends). Never pipe a gate through `tail` without pipefail.
- Biome auto-formats on every write via hook — never run it, never hand-align. If an Edit fails on whitespace, re-read and retry.
- Commit after each task, **explicit-path staging only** (parallel sessions; never `git add -A`).
- Work on a feature branch `filter-pane` off main.
- Operator labels are Title-Case with contractions: Is · Isn't · Doesn't Contain · Isn't Checked (B-4).
- Colors via design-system tokens only; no hand-rolled values.
- No-op-pass philosophy everywhere: a filter never excludes on what it can't apply (missing operand, dead property, unknown op, dead set id) — with the ONE deliberate exception inherited from Swift: tier/list `is`/`contains` with a missing SINGLE operand is false (filter.ts:246 comment).
- The dev app runs against Nathan's real Nexus — no live-app mutation tests; Vitest only.

## File Map

| File | Role |
| --- | --- |
| `Pommora/src/shared/views.ts` | `FilterRule.values?`, `MATCH_MODES` + `'none'`, exported `MatchMode` |
| `Pommora/src/shared/properties.ts` | `RESERVED_PROPERTY_ID.location: '_location'` |
| `Pommora/src/renderer/src/Detail/Views/pipeline/filter.ts` | op registry + all evaluator branches + `none` skip + location |
| `Pommora/src/renderer/src/Detail/Views/pipeline/resolveView.ts` | threads `setTree` into `applyFilter` |
| `Pommora/src/renderer/src/Detail/Views/pipeline/group.ts` | exports the existing `subtreeIds` + `buildSetTree` (module-local today) |
| `Pommora/src/renderer/src/Detail/Views/pipeline/contextOptions.ts` (new) | the hoisted `contextOptionsFor` (third consumer — TableView repoints) |
| `Pommora/src/renderer/src/Components/Detail/filterModel.ts` (new) | pure pane↔FilterGroup serializer + lock predicate + operator vocabulary |
| `Pommora/src/renderer/src/Components/Detail/FilterPane.tsx` (new) | the pane |
| `Pommora/src/renderer/src/Components/Detail/filterPane.css.ts` (new) | the pane's grid/field styles |
| `Pommora/src/renderer/src/Components/Detail/SettingsPane.tsx` | Filter leaf routes to the pane |
| `Pommora/src/renderer/src/Components/Detail/ViewSettings.tsx` | Filter leaf routes to the pane + new `tree` subscription |
| Tests | `views.test.ts` · `filter.test.ts` · `filterModel.test.ts` (new) · `FilterPane.test.tsx` (new) |

---

## Phase 1 — Data Model

### Task 1: `values[]` + `match: 'none'` in the shared codec

**Files:**
- Modify: `Pommora/src/shared/views.ts` (MATCH_MODES ~line 32, FilterRule ~69, filterRule/filterGroup codecs ~147–158)
- Modify: `Pommora/src/shared/properties.ts` (RESERVED_PROPERTY_ID ~line 127)
- Test: `Pommora/src/shared/views.test.ts`

**Interfaces:**
- Consumes: nothing new.
- Produces: `FilterRule.values?: string[]` · `MATCH_MODES = ['all','any','none']` · `export type MatchMode` · `RESERVED_PROPERTY_ID.location === '_location'`. Every later task relies on these exact names.

- [ ] **Step 1: Write the failing round-trip tests** (append to the existing `views.test.ts` describe block):

```ts
it('round-trips a filter with values[], match none, and nesting', () => {
  const view = savedView.parse({
    id: 'view_x',
    name: 'T',
    type: 'table',
    property_order: [],
    hidden_properties: [],
    filter: {
      match: 'none',
      rules: [
        {
          match: 'any',
          rules: [
            { property_id: 'prop_tags', op: 'contains_any', values: ['a', 'b'] },
            { match: 'all', rules: [{ property_id: 'prop_sel', op: 'is', value: 'x' }] }
          ]
        }
      ]
    }
  })
  const group = view.filter as FilterGroup
  expect(group.match).toBe('none')
  const inner = group.rules[0] as FilterGroup
  expect(inner.match).toBe('any')
  expect((inner.rules[0] as FilterRule).values).toEqual(['a', 'b'])
})
```

Add `FilterRule` to the test file's `@shared/views` type imports if absent.

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/shared/views.test.ts`
Expected: FAIL — zod `invalid_value` on `match: 'none'` (and `values` stripped).

- [ ] **Step 3: Implement.** In `views.ts`:

```ts
const MATCH_MODES = ['all', 'any', 'none'] as const
export type MatchMode = (typeof MATCH_MODES)[number]
```

Extend the `FilterRule` interface and doc comment:

```ts
/** One filter rule. `op` is a snake_case raw string (see FILTER_OPS in pipeline/filter.ts);
 *  `value` is the single serialized operand; `values` is the multi-operand set (chip ops:
 *  contains_all / contains_any / any-of Is / none-of Isn't). Both absent for presence ops. */
export interface FilterRule {
  property_id: string
  op: string
  value?: string
  values?: string[]
}
```

Extend the `FilterGroup` doc comment's last sentence: `match: 'none'` is the pane's disable state — root-only by authorship; the pipeline skips filtering when the ROOT is `none`, and a nested `none` evaluates as a pass.

Codec:

```ts
const filterRule = z.object({
  property_id: z.string(),
  op: z.string(),
  value: z.string().optional(),
  values: z.array(z.string()).optional()
})
```

(`filterGroup` needs no change — `z.enum(MATCH_MODES)` picks up `'none'` from the widened array.)

In `properties.ts`, add to `RESERVED_PROPERTY_ID`:

```ts
location: '_location',
```

(`_location` is the filter-only Location target — never a column; `declaredType` returns `undefined` for it, which is correct: the location branch runs BEFORE the type dispatch, Task 5.)

- [ ] **Step 4: Run to verify it passes**

Run: `npx vitest run src/shared/views.test.ts src/shared/properties.test.ts`
Expected: PASS.

- [ ] **Step 5: Gates + commit**

```bash
set -o pipefail
env -u ELECTRON_RUN_AS_NODE npm run typecheck && npx vitest run
git add Pommora/src/shared/views.ts Pommora/src/shared/properties.ts Pommora/src/shared/views.test.ts
git commit -m "feat(views): filter values[] operand + match 'none' + _location reserved id"
```

---

## Phase 2 — Evaluator

### Task 2: Op registry, `none` skip, `values[]` plumbing

**Files:**
- Modify: `Pommora/src/renderer/src/Detail/Views/pipeline/filter.ts`
- Test: `Pommora/src/renderer/src/Detail/Views/pipeline/filter.test.ts`

**Interfaces:**
- Consumes: Task 1's `values?`, `MatchMode`.
- Produces: `FILTER_OPS` gains `startsWith: 'starts_with'`, `containsAll: 'contains_all'`, `containsAny: 'contains_any'`, `isBefore: 'is_before'`, `isAfter: 'is_after'`, `greaterOrEqual: 'greater_or_equal'`, `lessOrEqual: 'less_or_equal'`, `isInside: 'is_inside'`, `isNotInside: 'is_not_inside'`. `applyFilter(rows, filter, schema, setTree?)` — root `none` returns rows. Per-type evaluators accept a trailing `values?: string[]`.

- [ ] **Step 1: Failing tests** (append to `filter.test.ts`):

```ts
describe('applyFilter — none + registry', () => {
  const rows = [row('r1', { props: { prop_sel: 'a' } }), row('r2', { props: { prop_sel: 'b' } })]

  it('a root match none skips filtering entirely', () => {
    expect(
      ids(rows, { match: 'none', rules: [{ match: 'all', rules: [{ property_id: 'prop_sel', op: 'is', value: 'a' }] }] })
    ).toEqual(['r1', 'r2'])
  })

  it('a NESTED none passes (root-only semantics)', () => {
    expect(
      ids(rows, { match: 'all', rules: [{ match: 'none', rules: [{ property_id: 'prop_sel', op: 'is', value: 'zzz' }] }] })
    ).toEqual(['r1', 'r2'])
  })

  it('registers every new op raw string', () => {
    expect(FILTER_OPS.startsWith).toBe('starts_with')
    expect(FILTER_OPS.containsAll).toBe('contains_all')
    expect(FILTER_OPS.containsAny).toBe('contains_any')
    expect(FILTER_OPS.isBefore).toBe('is_before')
    expect(FILTER_OPS.isAfter).toBe('is_after')
    expect(FILTER_OPS.greaterOrEqual).toBe('greater_or_equal')
    expect(FILTER_OPS.lessOrEqual).toBe('less_or_equal')
    expect(FILTER_OPS.isInside).toBe('is_inside')
    expect(FILTER_OPS.isNotInside).toBe('is_not_inside')
  })
})
```

- [ ] **Step 2: Run to verify failure** — `npx vitest run src/renderer/src/Detail/Views/pipeline/filter.test.ts` → FAIL (missing registry keys; `none` currently evaluates as OR).

- [ ] **Step 3: Implement.** In `filter.ts`:

Extend the registry (inside `FILTER_OPS`):

```ts
  startsWith: 'starts_with',
  containsAll: 'contains_all',
  containsAny: 'contains_any',
  isBefore: 'is_before',
  isAfter: 'is_after',
  greaterOrEqual: 'greater_or_equal',
  lessOrEqual: 'less_or_equal',
  isInside: 'is_inside',
  isNotInside: 'is_not_inside'
```

`applyFilter` gains the root-`none` skip and the (Task 5) `setTree` param now, so the signature changes once:

```ts
import type { SetTreeNode } from './group'

export function applyFilter(
  rows: ViewRow[],
  filter: FilterGroup | undefined,
  schema: PropertyDefinition[],
  setTree: SetTreeNode[] = []
): ViewRow[] {
  // 'none' = the pane's disable state (root-only): rules persist untouched, filtering skips.
  if (!filter || filter.match === 'none') return rows
  const locate = makeLocationIndex(setTree)
  return rows.filter((row) => matchesGroup(row, filter, schema, locate))
}
```

(`makeLocationIndex` lands in Task 5; THIS task ships its final type plus a callable stub, so the threaded signatures never change between tasks: `type LocationIndex = (setId: string) => ReadonlySet<string> | undefined` and `const makeLocationIndex = (_t: SetTreeNode[]): LocationIndex => () => undefined`. Thread `locate` through `matchesGroup`/`evaluateRule` unused. Nested `none`:)

```ts
function matchesGroup(row: ViewRow, group: FilterGroup, schema: PropertyDefinition[], locate: LocationIndex): boolean {
  if (group.match === 'none') return true // never pane-authored nested; a hand-authored one passes
  if (group.rules.length === 0) return true // empty filter = identity
  const results = group.rules.map((node) =>
    isGroup(node) ? matchesGroup(row, node, schema, locate) : evaluateRule(row, node, schema, locate)
  )
  return group.match === 'all' ? results.every(Boolean) : results.some(Boolean)
}
```

`evaluateRule` passes `rule.values` down; per-type evaluator signatures gain a trailing optional `values?: string[]` (only the branches Tasks 3–4 use it; the rest ignore it). Update the two `applyFilter` call sites' types compile-clean (default param keeps `resolveView` untouched until Task 5).

- [ ] **Step 4: Run to verify pass** — same command, PASS; whole suite green.

- [ ] **Step 5: Gates + commit**

```bash
set -o pipefail
env -u ELECTRON_RUN_AS_NODE npm run typecheck && npx vitest run
git add Pommora/src/renderer/src/Detail/Views/pipeline/filter.ts Pommora/src/renderer/src/Detail/Views/pipeline/filter.test.ts
git commit -m "feat(filter): op registry expansion + root-none skip + values plumbing"
```

### Task 3: Single-operand branches — number ≥/≤, date is/before/after, text starts_with

**Files:**
- Modify: `Pommora/src/renderer/src/Detail/Views/pipeline/filter.ts` (`evaluateNumber`, `evaluateDate`, `evaluateText`)
- Test: `filter.test.ts`

**Interfaces:**
- Consumes: Task 2's registry strings.
- Produces: the branches. Date `is` compares **calendar-day strings** (`iso.slice(0, 10)` both sides — B-7); `is_before`/`is_after` are strict ms comparisons beside the existing on_or ops; `starts_with` is case-insensitive (B-1).

- [ ] **Step 1: Failing tests:**

```ts
describe('applyFilter — new single-operand ops', () => {
  const rows = [
    row('n5', { props: { prop_num: 5 } }),
    row('n9', { props: { prop_num: 9 } }),
    row('d20', { props: { prop_when: '2026-06-20T14:30:00Z' } }),
    row('d25', { props: { prop_when: '2026-06-25' } }),
    row('sApple', { props: { prop_sel: 'apple' } }),
    row('sBanana', { props: { prop_sel: 'banana' } })
  ]

  it('number greater_or_equal / less_or_equal', () => {
    expect(ids(rows, { match: 'all', rules: [{ property_id: 'prop_num', op: 'greater_or_equal', value: '5' }] })).toEqual(['n5', 'n9', 'd20', 'd25', 'sApple', 'sBanana'])
    expect(ids([rows[0], rows[1]], { match: 'all', rules: [{ property_id: 'prop_num', op: 'less_or_equal', value: '5' }] })).toEqual(['n5'])
  })

  it('date is matches the CALENDAR DAY, ignoring the time component', () => {
    expect(ids([rows[2], rows[3]], { match: 'all', rules: [{ property_id: 'prop_when', op: 'is', value: '2026-06-20' }] })).toEqual(['d20'])
  })

  it('date is_before / is_after are strict', () => {
    expect(ids([rows[2], rows[3]], { match: 'all', rules: [{ property_id: 'prop_when', op: 'is_before', value: '2026-06-25' }] })).toEqual(['d20'])
    expect(ids([rows[2], rows[3]], { match: 'all', rules: [{ property_id: 'prop_when', op: 'is_after', value: '2026-06-20T14:30:00Z' }] })).toEqual(['d25'])
  })

  it('starts_with is case-insensitive; missing operand passes', () => {
    expect(ids([rows[4], rows[5]], { match: 'all', rules: [{ property_id: 'prop_sel', op: 'starts_with', value: 'APP' }] })).toEqual(['sApple'])
    expect(ids([rows[4], rows[5]], { match: 'all', rules: [{ property_id: 'prop_sel', op: 'starts_with' }] })).toEqual(['sApple', 'sBanana'])
  })
})
```

Note: `greater_or_equal` on rows without `prop_num` passes (no-op on null value) — hence the full-list expectation on the first assertion.

- [ ] **Step 2: Run to verify failure** (unregistered → all-pass makes the strict assertions fail).

- [ ] **Step 3: Implement.** `evaluateNumber` gains (mirroring the existing greaterThan shape):

```ts
    case FILTER_OPS.greaterOrEqual: {
      const e = parseNum(expected)
      return n === null || e === null ? true : n >= e
    }
    case FILTER_OPS.lessOrEqual: {
      const e = parseNum(expected)
      return n === null || e === null ? true : n <= e
    }
```

`evaluateDate` gains (day-string helper above the function):

```ts
/** Calendar-day comparison for date `is` (B-7): both sides truncated to their ISO date component —
 *  never exact-ms equality (a stored T14:30 must match its picked bare day). String-truncation, not
 *  Date math: the stored day IS the authored day regardless of the viewer's timezone. */
const dayOf = (iso: string): string => iso.slice(0, 10)
```

```ts
    case FILTER_OPS.is: {
      const raw = v.kind === 'datetime' ? v.value : null
      return raw === null || expected == null ? true : dayOf(raw) === dayOf(expected)
    }
    case FILTER_OPS.isBefore: {
      const e = parseDateMs(expected)
      return d === null || e === null ? true : d < e
    }
    case FILTER_OPS.isAfter: {
      const e = parseDateMs(expected)
      return d === null || e === null ? true : d > e
    }
```

`evaluateText` gains:

```ts
    case FILTER_OPS.startsWith:
      return s === null || expected == null ? true : s.toLowerCase().startsWith(expected.toLowerCase())
```

- [ ] **Step 4: Run to verify pass.**
- [ ] **Step 5: Gates + commit** (`git add` the two files; message `feat(filter): number gte/lte, date is/before/after, starts_with`).

### Task 4: Multi-operand branches — chips over `values[]`

**Files:**
- Modify: `filter.ts` (`evaluateText`, `evaluateMulti`, `evaluateList`)
- Test: `filter.test.ts`

**Interfaces:**
- Consumes: Task 2's `values` plumbing.
- Produces: Select/Status `is`/`is_not` read `values[]` as any-of/none-of when present (single `value` unchanged — B-5); `evaluateMulti` + `evaluateList` gain `contains_all`/`contains_any` and `values[]`-aware `does_not_contain`; **`contains_any` with an empty/missing set passes explicitly** (B-6's guard).

- [ ] **Step 1: Failing tests:**

```ts
describe('applyFilter — multi-operand values[]', () => {
  const rows = [
    row('a', { props: { prop_sel: 'a' } }),
    row('b', { props: { prop_sel: 'b' } }),
    row('ab', { props: { prop_tags: ['a', 'b'] } }),
    row('ac', { props: { prop_tags: ['a', 'c'] } }),
    row('t1', { tier1: ['area1', 'area2'] })
  ]

  it('select is with values[] = any-of; is_not = none-of', () => {
    expect(ids([rows[0], rows[1]], { match: 'all', rules: [{ property_id: 'prop_sel', op: 'is', values: ['a', 'zzz'] }] })).toEqual(['a'])
    expect(ids([rows[0], rows[1]], { match: 'all', rules: [{ property_id: 'prop_sel', op: 'is_not', values: ['a'] }] })).toEqual(['b'])
  })

  it('multi_select contains_all / contains_any / does_not_contain over values[]', () => {
    expect(ids([rows[2], rows[3]], { match: 'all', rules: [{ property_id: 'prop_tags', op: 'contains_all', values: ['a', 'b'] }] })).toEqual(['ab'])
    expect(ids([rows[2], rows[3]], { match: 'all', rules: [{ property_id: 'prop_tags', op: 'contains_any', values: ['b', 'zzz'] }] })).toEqual(['ab'])
    expect(ids([rows[2], rows[3]], { match: 'all', rules: [{ property_id: 'prop_tags', op: 'does_not_contain', values: ['b'] }] })).toEqual(['ac'])
  })

  it('contains_any with an EMPTY set passes — the mid-authoring guard', () => {
    expect(ids([rows[2], rows[3]], { match: 'all', rules: [{ property_id: 'prop_tags', op: 'contains_any', values: [] }] })).toEqual(['ab', 'ac'])
  })

  it('tier contains_all / contains_any', () => {
    expect(ids([rows[4]], { match: 'all', rules: [{ property_id: '_tier1', op: 'contains_all', values: ['area1', 'area2'] }] })).toEqual(['t1'])
    expect(ids([rows[4]], { match: 'all', rules: [{ property_id: '_tier1', op: 'contains_any', values: ['zzz'] }] })).toEqual([])
  })
})
```

(The last assertion is correct per the Swift-parity list exception: a tier membership test with a real-but-unmatched operand is false, not a pass.)

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement.** The set-shaped logic is ONE shared core — `evaluateMulti` and `evaluateList` would otherwise copy the same four guards and drift (the B-6 empty-set guard must live in one place):

```ts
/** The one set-membership core for multi_select AND id-lists (tiers/context). `want.length === 0`
 *  on the any-shaped ops passes — a mid-authoring empty chip set never blanks the table (B-6);
 *  contains_all passes empty for free ([].every()). Returns undefined for ops it doesn't own, so
 *  each caller keeps its own single-operand/presence branches. */
function matchesSet(xs: string[], op: Op, want: string[]): boolean | undefined {
  switch (op) {
    case FILTER_OPS.containsAny:
      return want.length === 0 ? true : want.some((w) => xs.includes(w))
    case FILTER_OPS.containsAll:
      return want.every((w) => xs.includes(w))
    default:
      return undefined
  }
}
```

`evaluateText(v, op, expected, values)`:

```ts
    case FILTER_OPS.is:
      if (values?.length) return s === null ? true : values.includes(s) // any-of (B-5)
      return s === null || expected == null ? true : s === expected
    case FILTER_OPS.isNot:
      if (values?.length) return s === null ? true : !values.includes(s) // none-of
      return expected == null ? true : s !== expected
```

`evaluateMulti(v, op, expected, values)` — the operand set is `values ?? (expected != null ? [expected] : [])` (single-value rules keep working, Swift parity):

```ts
  const want = values ?? (expected != null ? [expected] : [])
  const set = matchesSet(xs, op, want)
  if (set !== undefined) return set
  switch (op) {
    case FILTER_OPS.isEmpty:
      return xs.length === 0
    case FILTER_OPS.isNotEmpty:
      return xs.length > 0
    case FILTER_OPS.is:
    case FILTER_OPS.contains:
      // Empty set = mid-authoring → pass, NEVER exclude ([].some() would blank the table — B-6).
      return want.length === 0 ? true : want.some((w) => xs.includes(w))
    case FILTER_OPS.isNot:
    case FILTER_OPS.doesNotContain:
      return want.length === 0 ? true : !want.some((w) => xs.includes(w))
    default:
      return true
  }
```

`evaluateList(ids, op, expected, values)` calls the same `matchesSet` first, then keeps its OWN single-operand branches — including the documented Swift exception: `is`/`contains` with a missing single operand (and no `values`) stays **false**. Deliberate asymmetry, stated so nobody "fixes" it: the same no-operand condition passes under the chip-shaped ops (mid-authoring must not blank the table) and excludes under the legacy single-operand membership test (Swift parity, filter.ts:246's comment).

- [ ] **Step 4: Run to verify pass** (existing multi/tier tests must stay green — the single-value paths are untouched).
- [ ] **Step 5: Gates + commit** (`feat(filter): values[] any-of/none-of + contains_all/any across text, multi, list`).

### Task 5: Title, Context membership, Location

**Files:**
- Modify: `filter.ts` (title branch, context/file split, `makeLocationIndex` + `_location` branch)
- Modify: `Pommora/src/renderer/src/Detail/Views/pipeline/group.ts` (export the existing `subtreeIds` at ~line 266 — hoist it from its closure to module scope; the filter's index reuses it rather than re-rolling the walk)
- Modify: `resolveView.ts:26` (thread `setTree`)
- Test: `filter.test.ts` (including the two pinned-test INVERSIONS — restate, don't append contradictions)

**Interfaces:**
- Consumes: Tasks 1–4. `RESERVED_PROPERTY_ID.location`. `SetTreeNode` from `./group`.
- Produces: `_title` rules evaluate as text; `context` type routes to `evaluateList` (`file` stays presence-only); `_location` + `is_inside`/`is_not_inside` membership-test the row's `parentSetId` against a **precomputed per-rule descendant Set** (C-3); a dead set id passes.

- [ ] **Step 1: Restate the two pinned no-op tests + add the new coverage.** DELETE the `'a _title rule passes (not in the filter matrix, Swift parity)'` test and the user-relation half of the tier test's no-op assertion; write:

```ts
describe('applyFilter — title, context membership, location', () => {
  const tree = [
    { id: 'set_a', children: [{ id: 'set_a1', children: [] }] },
    { id: 'set_b', children: [] }
  ]
  const inA1 = { ...row('inA1'), parentSetId: 'set_a1' }
  const inB = { ...row('inB'), parentSetId: 'set_b' }
  const atRoot = row('atRoot')
  const loc = (rows: ViewRow[], op: string, value: string): string[] =>
    applyFilter(rows, { match: 'all', rules: [{ property_id: '_location', op, value }] }, schema, tree).map((r) => r.id)

  it('title filters as text (Is / Starts With / Contains)', () => {
    const rows = [row('Apple Pie'), row('Banana')]
    expect(ids(rows, { match: 'all', rules: [{ property_id: '_title', op: 'starts_with', value: 'app' }] })).toEqual(['Apple Pie'])
    expect(ids(rows, { match: 'all', rules: [{ property_id: '_title', op: 'contains', value: 'NAN' }] })).toEqual(['Banana'])
  })

  it('user context filters by membership like tiers', () => {
    const rRel = row('rRel', { props: { prop_rel: [{ $ctx: 'x' }] } })
    const rNone = row('rNone')
    expect(ids([rRel, rNone], { match: 'all', rules: [{ property_id: 'prop_rel', op: 'is', value: 'x' }] })).toEqual(['rRel'])
    expect(ids([rRel, rNone], { match: 'all', rules: [{ property_id: 'prop_rel', op: 'contains_any', values: ['x', 'y'] }] })).toEqual(['rRel'])
  })

  it('is_inside matches any depth; is_not_inside inverts; root pages are inside nothing', () => {
    expect(loc([inA1, inB, atRoot], 'is_inside', 'set_a')).toEqual(['inA1'])
    expect(loc([inA1, inB, atRoot], 'is_not_inside', 'set_a')).toEqual(['inB', 'atRoot'])
  })

  it('a dead set id is a no-op pass', () => {
    expect(loc([inA1, inB], 'is_inside', 'set_ghost')).toEqual(['inA1', 'inB'])
  })
})
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement.** In `filter.ts` — the location index (replaces Task 2's stub):

```ts
type LocationIndex = (setId: string) => ReadonlySet<string> | undefined

/** Per-applyFilter location index: each is_inside operand resolves ONCE to its descendant-id Set
 *  (self included), then every row is an O(1) parentSetId membership test — never a per-row
 *  ancestor walk (C-3, the "never on every X" rule). Unknown set id → undefined → no-op pass. */
function makeLocationIndex(setTree: SetTreeNode[]): LocationIndex {
  const cache = new Map<string, ReadonlySet<string> | undefined>()
  const find = (nodes: SetTreeNode[], id: string): SetTreeNode | undefined => {
    for (const n of nodes) {
      if (n.id === id) return n
      const hit = find(n.children, id)
      if (hit) return hit
    }
    return undefined
  }
  return (setId) => {
    if (!cache.has(setId)) {
      const node = find(setTree, setId)
      cache.set(setId, node ? new Set(subtreeIds(node)) : undefined)
    }
    return cache.get(setId)
  }
}
```

(`subtreeIds` imports from `./group` — hoist the existing closure-local walk at group.ts:266 to an exported module-scope function; its one internal caller keeps working. Never re-roll the walk.)

In `evaluateRule`, BEFORE the `declaredType` dispatch (beside the `_modified_at` branch):

```ts
  // Location — not a property: membership of the row's parent set in the operand's subtree.
  if (rule.property_id === RESERVED_PROPERTY_ID.location) {
    if (rule.op !== FILTER_OPS.isInside && rule.op !== FILTER_OPS.isNotInside) return true
    const inside = rule.value != null ? locate(rule.value) : undefined
    if (!inside) return true // dead/missing set id → no-op pass
    const hit = row.parentSetId != null && inside.has(row.parentSetId)
    return rule.op === FILTER_OPS.isInside ? hit : !hit
  }
```

Title branch in `evaluateByType` (replacing `title`'s fall-through to default):

```ts
    case 'title':
      return evaluateText(v, op, expected, values)
```

(`resolveFieldValue('_title')` already returns `{kind:'select', value: row.title}` — `textValue` reads it directly.)

Context split (replacing the shared arm):

```ts
    case 'context':
      return evaluateList(v.kind === 'context' ? v.value : [], op, expected, values)
    case 'file':
      return evaluatePresence(v, op)
```

Update the file-head doc comment: title + context are now first-class matrices; `_location`/`is_inside` documented beside `_modified_at`. In `resolveView.ts:26`:

```ts
  const filtered = applyFilter(rows, view.filter, schema, setTree)
```

- [ ] **Step 4: Run to verify pass** — full pipeline suite (`filter` + `resolveView` + `group` + `sort` tests) green.
- [ ] **Step 5: Full gates + commit** (add `filter.ts`, `filter.test.ts`, `resolveView.ts`; `feat(filter): title text matrix, context membership, any-depth location`). **Phase-end: run the build gate too.**

---

## Phase 3 — The Pane

### Task 6: `filterModel.ts` — the pure pane↔tree serializer + vocabulary

**Files:**
- Create: `Pommora/src/renderer/src/Components/Detail/filterModel.ts`
- Test: `Pommora/src/renderer/src/Components/Detail/filterModel.test.ts`

**Interfaces:**
- Consumes: `FilterRule`/`FilterGroup`/`MatchMode` (Task 1), `FILTER_OPS` (Task 2), `declaredType` (pipeline/value), `RESERVED_PROPERTY_ID`, `propertyTypeIconName`/`TITLE_META` (PropertyTypes), `asRenderableIcon`.
- Produces (the pane consumes ALL of these exact names):

```ts
export type Connector = 'and' | 'or'
export interface PaneRow { connector: Connector | null; rule: FilterRule } // null on row 0
export type DecodedFilter =
  | { kind: 'rows'; enabled: boolean; mode: 'all' | 'any'; rows: PaneRow[] }
  | { kind: 'locked'; enabled: boolean } // un-flattenable hand-authored tree
export function decodeFilter(filter: FilterGroup | undefined): DecodedFilter
export function encodeFilter(enabled: boolean, rows: PaneRow[]): FilterGroup | undefined
export type ValueSlot = 'none' | 'text' | 'number' | 'date' | 'chips' | 'set'
export interface OperatorChoice { op: string; label: string; slot: ValueSlot; multi?: boolean }
export function operatorsFor(propertyId: string, schema: PropertyDefinition[]): OperatorChoice[]
export interface FilterTarget { id: string; label: string; icon: IconName | undefined }
export function filterTargets(schema: PropertyDefinition[]): FilterTarget[]
```

**Semantics (all from the certified log):**
- `encodeFilter`: connectors derive the tree — split rows into runs at each `'or'`; one run of one rule → `{match:'all', rules:[rule]}`… no: one run → root `{match:'all', rules: leaves}`; 2+ runs → `{match:'any', rules: runs.map(run => run.length === 1 ? run[0] : {match:'all', rules: run})}`. Zero rows → `undefined` when enabled. **Disabled wraps losslessly (A-4):** `{match:'none', rules:[<the enabled-form root>]}`; zero rows disabled → `{match:'none', rules:[]}`.
- `decodeFilter`: `match:'none'` → unwrap the single child group (or empty) and decode it with `enabled:false`; a `none` root whose rules aren't `[]`/`[group]` is locked-disabled. Editable shapes (A-2, by SHAPE): `{all, rules: all leaves}` → mode `all`, connectors `and`; `{any, rules: (leaf | {all, leaves})[]}` → runs rejoin with `'or'` between runs, `'and'` within; mode is `any` only when every child is a leaf (all-or), else `all` (mixed reads All — D-10). Anything else — deeper nesting, a nested `any`, a nested `none` — → `{kind:'locked'}`.
- `operatorsFor` (labels Title-Case contractions — B-4/B-5): title → Is/Isn't/Starts With/Contains/Doesn't Contain (text); select/status → Is/Isn't (chips, `multi: true`, writes `values[]`) + Is Empty/Isn't Empty; multi_select → Is Any (`contains_any`)/Is All (`contains_all`)/Isn't (`does_not_contain`) (chips multi) + empties; tier/context → same as multi_select; number → Is/Isn't/≥ `Is at Least`… **labels:** Is/Isn't/Greater Than/At Least/Less Than/At Most + empties (number slot); datetime/modified → Is/Is Before/Is After/Is On or Before/Is On or After (date slot) + empties; checkbox → Is Checked (`is`+`value:'true'`)/Isn't Checked (`is`+`value:'false'`) — slot `none`, the operator carries the whole clause; url → Is/Isn't/Contains/Doesn't Contain/Starts With (text) + empties; file → Has File (`is_not_empty`)/No File (`is_empty`); location → Is Inside/Isn't Inside (set slot). Empty ops are slot `none`.
- `filterTargets`: `[Title (TITLE_META.icon), Location (icon 'folder'), Modified (propertyTypeIconName('last_edited_time')), Areas/Topics/Projects (_tier1/2/3, icon 'layout-grid'), ...schema]` — every schema def whose `declaredType` has a non-empty operator vocabulary (which is all current types), icon `asRenderableIcon(d.icon) ?? propertyTypeIconName(d.type)` (the sortTargets pattern).

- [ ] **Step 1: Write the tests first** — the load-bearing set:

```ts
import { describe, expect, it } from 'vitest'
import { decodeFilter, encodeFilter, operatorsFor, filterTargets } from './filterModel'

const r = (id: string, op = 'is', value = 'x') => ({ property_id: id, op, value })

describe('encodeFilter', () => {
  it('all-and → flat all group', () => {
    expect(encodeFilter(true, [{ connector: null, rule: r('a') }, { connector: 'and', rule: r('b') }]))
      .toEqual({ match: 'all', rules: [r('a'), r('b')] })
  })
  it('A and B, or C → any of [all-run, leaf]', () => {
    expect(encodeFilter(true, [
      { connector: null, rule: r('a') }, { connector: 'and', rule: r('b') }, { connector: 'or', rule: r('c') }
    ])).toEqual({ match: 'any', rules: [{ match: 'all', rules: [r('a'), r('b')] }, r('c')] })
  })
  it('no rows enabled → undefined; disabled wraps losslessly', () => {
    expect(encodeFilter(true, [])).toBeUndefined()
    expect(encodeFilter(false, [{ connector: null, rule: r('a') }]))
      .toEqual({ match: 'none', rules: [{ match: 'all', rules: [r('a')] }] })
  })
})

describe('decodeFilter', () => {
  it('round-trips every editable shape bit-identically', () => {
    const shapes = [
      encodeFilter(true, [{ connector: null, rule: r('a') }]),
      encodeFilter(true, [{ connector: null, rule: r('a') }, { connector: 'or', rule: r('b') }]),
      encodeFilter(true, [{ connector: null, rule: r('a') }, { connector: 'and', rule: r('b') }, { connector: 'or', rule: r('c') }]),
      encodeFilter(false, [{ connector: null, rule: r('a') }, { connector: 'or', rule: r('b') }])
    ]
    for (const tree of shapes) {
      const d = decodeFilter(tree)
      expect(d.kind).toBe('rows')
      if (d.kind === 'rows') expect(encodeFilter(d.enabled, d.rows)).toEqual(tree)
    }
  })
  it('mixed connectors read mode all; pure or reads any (D-10)', () => {
    const mixed = decodeFilter({ match: 'any', rules: [{ match: 'all', rules: [r('a'), r('b')] }, r('c')] })
    expect(mixed.kind === 'rows' && mixed.mode).toBe('all')
    const pureOr = decodeFilter({ match: 'any', rules: [r('a'), r('b')] })
    expect(pureOr.kind === 'rows' && pureOr.mode).toBe('any')
  })
  it('locks the shallow trap: an any nested under an all root', () => {
    expect(decodeFilter({ match: 'all', rules: [r('a'), { match: 'any', rules: [r('b'), r('c')] }] }).kind).toBe('locked')
  })
  it('locks 3-deep nesting', () => {
    expect(decodeFilter({ match: 'any', rules: [{ match: 'all', rules: [r('a'), { match: 'any', rules: [r('b')] }] }] }).kind).toBe('locked')
  })
  it('undefined → enabled empty rows', () => {
    expect(decodeFilter(undefined)).toEqual({ kind: 'rows', enabled: true, mode: 'all', rows: [] })
  })
})

describe('vocabulary', () => {
  const schema = [
    { id: 'prop_sel', name: 'Sel', type: 'select' as const },
    { id: 'prop_done', name: 'Done', type: 'checkbox' as const }
  ]
  it('checkbox operators carry the whole clause (slot none)', () => {
    const ops = operatorsFor('prop_done', schema)
    expect(ops.map((o) => o.label)).toEqual(['Is Checked', "Isn't Checked"])
    expect(ops.every((o) => o.slot === 'none')).toBe(true)
  })
  it('select reads Is/Isn\'t/Is Empty/Isn\'t Empty with chip slots', () => {
    expect(operatorsFor('prop_sel', schema).map((o) => o.label)).toEqual(['Is', "Isn't", 'Is Empty', "Isn't Empty"])
  })
  it('targets lead Title · Location · Modified · tiers, then schema', () => {
    expect(filterTargets(schema).map((t) => t.label).slice(0, 6)).toEqual(['Title', 'Location', 'Modified', 'Areas', 'Topics', 'Projects'])
  })
})
```

(Tier labels come from the nexus labels at the PANE layer — the model uses the default Areas/Topics/Projects and the pane overrides with `tierLabel(level, labels)` when the tree provides labels; keep the model pure.)

- [ ] **Step 2: Run to verify failure** (module doesn't exist).
- [ ] **Step 3: Implement the module to the exact semantics above.** Keep it pure (no React); `encodeFilter` builds runs with a simple accumulator; `decodeFilter` validates shape with two small predicates (`isLeaf`, `isAllOfLeaves`). Checkbox choices: `{ op: FILTER_OPS.is, label: 'Is Checked', slot: 'none' }` carries an implied `value: 'true'` — expose it as `impliedValue?: string` on `OperatorChoice` so the pane writes it on pick.
- [ ] **Step 4: Run to verify pass.**
- [ ] **Step 5: Gates + commit** (`feat(filter): filterModel — pane↔tree serializer, lock predicate, operator vocabulary`).

### Task 7: FilterPane — structure, Matches row, rule rows, hosting

**Files:**
- Create: `Pommora/src/renderer/src/Components/Detail/FilterPane.tsx`
- Create: `Pommora/src/renderer/src/Components/Detail/filterPane.css.ts`
- Modify: `SettingsPane.tsx` (route the filter leaf; pass `tree`), `ViewSettings.tsx` (route; add `const tree = useSession((s) => s.tree)`)
- Test: `Pommora/src/renderer/src/Components/Detail/FilterPane.test.tsx`

**Interfaces:**
- Consumes: Task 6's model wholesale; the chassis (`MenuPaneTopRow`, `MenuItem`, `MenuSeparator`, `PickerControl`, `PickerMenu`, `Reveal`, `gp.middle`, `saveViewAdopting`); `NexusTree` for contexts + labels.
- Produces:

```ts
export function FilterPane(props: {
  source: CollectionNode | SetNode
  view: SavedView
  schema: PropertyDefinition[]
  tree: NexusTree | null
  label: string // breadcrumb: 'Settings' | 'Views'
  onBack: () => void
}): React.JSX.Element
```

**Structure (F-1…F-3, F-6…F-8):**
- `MenuPaneTopRow label={label} current="Filtering"` · the **Matches** ValueRow (no leading icon — a `MenuItem` with trailing `PickerControl` over `[{value:'all',label:'All'},{value:'any',label:'Any'},{value:'none',label:'None'}]`, `gp.pickerTone`) · `MenuSeparator flush` · the rule region (`gp.middle` + `overflow-eclipse-y`) · `MenuSeparator flush` · the footer "+" row.
- The rule region is ONE CSS grid (`filterPane.css.ts`): `gridTemplateColumns: 'max-content minmax(72px, 1.4fr) fit-content(140px) minmax(72px, 1fr)'` (connector · what · operator · value), `columnGap: 6px`, `rowGap: 4px`, padding `4px 8px`; the whole pane root sets `maxWidth: FILTER_MAX_WIDTH` (**KNOB**, start `420px`).
- Each field is a button/div wearing the EXISTING recipes — import `field` from `interactionField.css` (and lean on `textPicker.css`'s `input`/`suffixField` variants for the typed slots); don't mint a `filterField` style unless the grid-cell metrics genuinely diverge once rendered (the geometry isn't settled until Task 9 — a pre-committed new style is the over-build). `label.control` tone, inside `chevrons-up-down` at 12px for the two trigger fields. What field leads with the target's `Icon` at 13px.
- Connector: row 0 renders an empty grid cell; rows 1+ a mini field in `gp.subLabel` tone showing `And`/`Or` + the double-chevron; **onClick toggles the connector directly** and saves.
- Row removal: a trailing hover-revealed × (`circle-x` 12px) absolutely placed at the row's right inside the value cell's gutter — `opacity: 0` at rest, `1` on `:hover` of the grid row (a `filterRow` wrapper class with `display: contents` won't hover — use a per-row `gridColumn: '1 / -1'` overlay… simplest correct: each row IS four cells plus a fifth 16px `max-content` column for the ×; the × button gets the ghost-reveal styles). Grid becomes 5 columns: `max-content minmax(72px,1.4fr) fit-content(140px) minmax(72px,1fr) 16px`.
- Disabled (`enabled === false`): the rule region + footer get a `paneDisabled` class — `opacity: 'var(--state-ghost)'`, `pointerEvents: 'none'` — the Matches row stays live (F-7).
- Locked (`decoded.kind === 'locked'`): the region renders a `MenuCaption`-style line "Hand-authored filter" over a single footing-recipe **Reset** row (confirm-free: it writes `undefined` when enabled — the explicit user action IS the confirmation, A-2).
- Every mutation: rebuild rows → `saveViewAdopting(source, { ...view, filter: encodeFilter(enabled, rows) }, load)` — wholesale slot ownership.
- The "+" footer row (bare `plus` glyph, footing recipe) appends `{ connector: rows.length ? mode-as-connector : null, rule: { property_id: '', op: '' } }` held in LOCAL draft state until the row gains a target (an incomplete row is never written — and once written mid-authoring it's a no-op pass anyway, F-7). Placeholder fields render `label.tertiary` "Property" / "Condition". **The draft's lifecycle is explicit — the chassis holds no precedent for local state vs refetch:** (a) completing the draft **clears it synchronously in the same handler that dispatches the write** — the decoded row arrives on the refetch, never double-rendering beside a lingering draft; (b) both hosts mount the pane **`key={view.id}`**, so a view switch while the leaf is open remounts it and a stale draft can never float onto another view's rows.
- What field opens a beaked `PickerMenu` listing `filterTargets` (pane overrides tier labels via `tierLabel(level, tree.labels)` when `tree` present); picking a target writes the rule with the type's FIRST operator and clears operands. Operator field likewise over `operatorsFor` (picking writes `op` + `impliedValue` + drops stale operands when the slot changed).

- [ ] **Step 1: Failing tests** (the GroupingPane.test harness: `createRoot`/`act`, ResizeObserver stub, spy on `window.nexus.views.save` — copy the existing test scaffold from `SortingPane.test.tsx`): (a) renders Matches All + a row per decoded rule; (b) Matches → None writes the wrapped `{match:'none', rules:[…]}` and the region gains the disabled class; (c) toggling a connector And→Or re-serializes to any-of-runs; (d) a locked tree renders the Reset row and no rule grid; (e) "+" adds a placeholder row without writing; picking a property writes the first operator.
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** `FilterPane.tsx` + `filterPane.css.ts` per the structure above; route the hosts:

`SettingsPane.tsx` — replace the `blankLeaf` fall-through for filter:

```tsx
    ) : detailId === 'filter' ? (
      (() => {
        const v = pickView(node, activeViewId, schema)
        return <FilterPane key={v.id} source={node} view={v} schema={schema} tree={tree} label="Settings" onBack={back} />
      })()
    ) : (
```

`ViewSettings.tsx` — add `const tree = useSession((s) => s.tree)` beside `load`, and replace the filter leaf's bare `MenuPaneTopRow`:

```tsx
    ) : leaf === 'filter' ? (
      <FilterPane key={view.id} source={source} view={view} schema={schema} tree={tree} label="Views" onBack={() => setLeaf(null)} />
    ) : leaf ? (
```

Update both files' "Filter ships blank-leafed" comments — they're now false; restate to the durable truth.

- [ ] **Step 4: Run to verify pass.**
- [ ] **Step 5: Gates + commit** (add the four files + tests; `feat(filter): the FilterPane — matches row, rule grid, both doors`).

### Task 8: Value editors — text/number, date, chips, set picker

**Files:**
- Modify: `FilterPane.tsx` (+ `filterPane.css.ts`)
- Create: `Pommora/src/renderer/src/Detail/Views/pipeline/contextOptions.ts` (the hoisted `contextOptionsFor`)
- Modify: `Pommora/src/renderer/src/Detail/Views/Table/TableView.tsx` (~:535 — repoint its private closure to the shared helper), `pipeline/group.ts` (export `buildSetTree`)
- Test: `FilterPane.test.tsx`

**Interfaces:**
- Consumes: `CalendarPicker` (`design-system/components/CalendarPicker`), `formatDate`/`styleFor` (PropertyEditing), `Chip`/`chipShapeForType`/`chipColorFor`, `ContextChip`, `PickerMenu`/`PickerOption`, `optionsOf` (GroupingPane export), `statusOptions` (`@shared/properties`), `condensedDate`, `buildSetTree` (pipeline/group, exported this task).
- Produces: the per-slot value cell, switched on the picked `OperatorChoice.slot`:
  - **`none`** — empty cell (checkbox, empties, file).
  - **`text`** — an `<input>` on the `textPicker.input` recipe (import the style), committing on blur/Enter into `rule.value`.
  - **`number`** — same input with `inputMode="decimal"`; commit writes the raw string (the evaluator parses).
  - **`date`** — a trigger field showing the value via the property's assigned format: `formatDate(rule.value, …styleFor(view.column_styles?.[propertyId], type))` — the F-4 rule; the property's own format, default when unstyled; opens `CalendarPicker` in a `PickerMenu` (`range={false}`, `formatDateValue` from the same style, `onChange` commits the ISO into `rule.value`). The picker dismisses on view switch (E-4) — it's mounted under the pane, which unmounts with the dropdown; no extra wiring needed, note it in the test.
  - **`chips`** (`multi: true` ops) — the **filter-owned picker host** (B-5/D-4): the field shows the picked chips (`values[]` → option lookup → `Chip`/`ContextChip` at `gp.subChip` zoom, Status as pill with `onRemove` hover-× that strips the value from `values[]`); clicking the field opens a `PickerMenu` of `PickerOption`s that **toggle the value in `values[]` and stay open** — never `PropertyPicker`, never a PropertyValue commit. Options: select/status/multi via `optionsOf(def)`; tiers + context defs via `contextOptionsFor(level, tree)` — **extracted this task**: the mapping is a private closure inside TableView.tsx (~:535) about to gain its third consumer, so hoist it to a shared `contextOptions.ts` beside `pipeline/value.ts` (`export function contextOptionsFor(level: number, tree: NexusTree): Array<{ value: string; label: string; color?: string }>`), repoint TableView's closure to it, and resolve a user def's level via `context_target.tier`.
  - **`set`** (location) — a trigger field opening a `PickerMenu` of the set tree flattened depth-first with indentation. **No new prop threading:** derive it locally the way the evaluator and LocationHierarchy both already do — export `buildSetTree` from `pipeline/group.ts` (~:47, currently module-local) and call `buildSetTree(source.sets)` inside the pane. Picking writes the set id into `rule.value`; the field shows the set's title (dead id → the raw id, dimmed).

- [ ] **Step 1: Failing tests:** (a) a chips-op row toggles two options through the stay-open picker and the save spy receives `values: ['x','y']` (and NO `value` key); (b) removing a chip via its × strips it from `values[]`; (c) a checkbox row writes `op: 'is', value: 'true'` with no value cell rendered; (d) a date row's field shows the formatted day and a CalendarPicker commit writes the ISO.
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** the slot switch + the chip picker host component (`FilterChipsField`, local to FilterPane.tsx unless it clears ~80 lines — then a sibling file).
- [ ] **Step 4: Run to verify pass.**
- [ ] **Step 5: Gates + commit** (`feat(filter): per-slot value editors — text, number, date, chips, set`).

### Task 9: Checkbox operator glyphs + geometry polish

**Files:**
- Modify: `FilterPane.tsx`, `filterPane.css.ts`

**Interfaces:**
- Consumes: `checkbox_color` off the def (`properties.ts` def-level key), the solid palette map (`chipColorFor`/solid tokens).
- Produces: F-5 — the checkbox operator options (in the operator PickerMenu AND the closed field) lead with a 12px checkbox glyph: `square` (empty) for Isn't Checked, `square-check` for Is Checked, the checked one tinted the def's `checkbox_color` solid (absent → `var(--accent)`). Grid geometry verified against D-9: operator column `fit-content` sized by its widest label, What/Value split spare space, everything truncates behind the eclipse — adjust `FILTER_MAX_WIDTH` and the minmax floors as needed.

- [ ] **Step 1: Implement the glyphs** (no failing test first — visual; assert in the existing operator-picker test that the checkbox choices render `square-check`/`square` icons).
- [ ] **Step 2: Run the pane test suite; then the full gates including the build.**
- [ ] **Step 3: Commit** (`feat(filter): checkbox operator glyphs + grid geometry knobs`).

### Task 10: Docs + closeout

**Files:**
- Modify: `.claude/Features/Views.md` (the Filter pipeline bullet → full truth: operators, title/location/context, `none`, `values[]`, lock state; the Surfaces section gains the Filtering pane paragraph in the Grouping/Sorting register; Pending drops the Filter line), `.claude/Features/Properties.md` (only if it restates filter ops), `.claude/History.md` (one entry: the FilterPane + evaluator extension, the locked decisions — none-wrapping, shape-lock, values[]), `.claude/Handoff.md` (session block per /handoff conventions — or leave for /handoff).

- [ ] **Step 1: Restate the docs to the shipped truth** — durable voice, no correction-narration; wiki-link Views ↔ Properties where they cross-reference.
- [ ] **Step 2: Full gates** (`set -o pipefail; env -u ELECTRON_RUN_AS_NODE npm run typecheck && npx vitest run && env -u ELECTRON_RUN_AS_NODE npm run build`).
- [ ] **Step 3: Commit docs** (explicit paths; `docs(views): filtering — pane, evaluator matrix, none/values/lock semantics`).
- [ ] **Step 4: Post-build verification pass** — dispatch build-breaking-agent on the working tree (post-green discipline), then code-simplifier; fold verified findings. Live UIX review with Nathan (HMR) before closeout — post-functional UIX review is mandatory.

---

## Self-Review Notes (run at write time)

- Spec coverage: A-1→Task 6 · A-2→6/7 · A-3→1/4 · A-4→1/2/6/7 · A-5→4/7 · B-1→2/3 · B-2→3 · B-3→3 · B-4/B-5→4/6 · B-6→2/4 · B-7→3 · C-1→6 · C-2→5 · C-3→5 · C-4→6 (Created absent) · C-5/C-6→4/5/8 · C-7→6 (file presence ops) · C-8→7/8 · D-1…D-10→6/7/8/9 · E-1→1–8 · E-2→10 · E-4→8 (note) · F-1…F-8→7/8/9. E-3 (badge) is a Prospect — no task, correct.
- The pane never writes an incomplete rule (local placeholder state, Task 7) AND the evaluator no-op-passes anything half-written that does land — both layers hold A-5.
- Type-consistency: `encodeFilter(enabled, rows)`/`decodeFilter(filter)`/`operatorsFor(propertyId, schema)`/`filterTargets(schema)`/`OperatorChoice.impliedValue` used identically in Tasks 6–9.
