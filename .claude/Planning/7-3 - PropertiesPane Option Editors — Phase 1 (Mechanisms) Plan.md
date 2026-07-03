# PropertiesPane Option Editors — Phase 1 (Mechanisms) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the option-CRUD backend + data-model changes for Select/Multi/Status option editing — no pane UI — so Phases 2-3 render over a proven, tested mechanism layer.

**Architecture:** Data-model changes land in `src/shared` (the color key opens up, the Status seed relabels, a pure option-editing model). New main-process ops (`setOptions`, `renameOption`, `removeOption`, `clearOption`) ride the existing serialization chains — registry-only edits on `mutateRegistry`, page-touching edits on `serializeSchemaOp` — and a new per-value page-strip primitive sits beside `stripPageMember`. IPC follows the existing `schema:*` handler + preload-bridge pattern verbatim.

**Tech Stack:** TypeScript, Zod (schemas), Vitest (tests), Electron main/preload/renderer split. Files at `React/`. Run tests with `npx vitest run <path>` from `React/`.

## Global Constraints

- **Value is title:** an option's `value` equals its `label` equals its user-facing title for every new/edited option. Rename changes both and cascades page frontmatter values. Uniqueness = no two options in one property share a title (the existing unique-value check, run on edits).
- **Color is an open solid-palette key:** option color is a permissive string storing a `colors.css` solid key (red/orange/yellow/green/lightBlue/cyan/blue/purple/lavender/grey); `chipColorFor` normalizes (solid keys pass through, legacy Notion values map, unknown → `default`). Swift on-disk compatibility is NOT a constraint.
- **Two chains, never crossed:** registry-only ops go through `mutateRegistry` (`io/propertiesRegistry.ts`); page-touching ops go through `serializeSchemaOp` (`crud/schemaChain.ts`).
- **IPC never throws across the boundary:** every handler returns `{ ok: true, … } | { ok: false, error: string }`.
- **No expensive work on every X:** no full re-walks where a targeted read works.
- **Colors authored as hex** live only in `design-system/tokens`; this plan touches token *keys*, never literals.
- **Biome auto-formats on write** — write correct code, never hand-align; `npm run typecheck` is the only type gate.
- **Confirm dialogs are Phase 2**, not here: `removeOption`/`clearOption` are unconfirmed backend ops (exactly as `property:delete` is unconfirmed and the confirm lives in `popPropertyMenu`). Phase 2's option menu will pop the confirm before calling them.

---

## File Structure

- **Modify `src/shared/properties.ts`** — open the option `color` field (permissive string); relabel `defaultStatusSeed()` to Open/Active/Done with value=title + group colors; add `legacyStatusSeed()`; make `isUntouchedSeed()` recognize both seeds; align `defaultSelectSeed()` to value=title.
- **Modify `src/renderer/src/design-system/tokens/colorMap.ts`** — `chipColorFor` passes solid keys through before the legacy map.
- **Create `src/shared/optionModel.ts`** — pure option-array helpers (add/rename/recolor/reorder/fallback/unique-title) usable by the renderer and tested in isolation.
- **Modify `src/main/properties/schema.ts`** — drop the ≥1-option floor in `validateDefinition`; add `validateOptionValues` (unique) for edit-time use.
- **Create `src/main/crud/pageValue.ts`** — the per-value page primitives: `stripPageValue` (remove one option's value) and `replacePageValue` (rename cascade), type-switched over select/status/multi.
- **Create `src/main/crud/optionOps.ts`** — `setOptions`, `renameOption`, `removeOption`, `clearOption` on the correct chains.
- **Modify `src/preload/index.ts`** — add the four ops to the `schema` bridge block.
- **Modify `src/main/index.ts`** — register the four `schema:*Option` handlers.

---

## Task 1: Open the Option Color Key

**Files:**
- Modify: `src/shared/properties.ts` (the `selectOption` / `statusOption` / `statusGroup` color fields)
- Modify: `src/renderer/src/design-system/tokens/colorMap.ts` (`chipColorFor`)
- Test: `src/renderer/src/design-system/tokens/colorMap.test.ts` (create if absent)

**Interfaces:**
- Produces: `chipColorFor(color: string | undefined): ChipColorName` — now passes through any key already in the chip palette before consulting the legacy Notion map.

- [ ] **Step 1: Write the failing test** — `colorMap.test.ts`:

```typescript
import { describe, it, expect } from 'vitest'
import { chipColorFor } from './colorMap'

describe('chipColorFor — open solid-palette keys', () => {
  it('passes solid keys straight through (incl lightBlue)', () => {
    for (const key of ['red', 'orange', 'yellow', 'green', 'lightBlue', 'cyan', 'blue', 'purple', 'lavender', 'grey'] as const) {
      expect(chipColorFor(key)).toBe(key)
    }
  })
  it('still maps legacy Notion names for old data', () => {
    expect(chipColorFor('gray')).toBe('grey')
    expect(chipColorFor('teal')).toBe('cyan')
    expect(chipColorFor('pink')).toBe('lavender')
    expect(chipColorFor('brown')).toBe('orange')
    expect(chipColorFor('indigo')).toBe('purple')
  })
  it('falls to default for unknown / absent', () => {
    expect(chipColorFor('chartreuse')).toBe('default')
    expect(chipColorFor(undefined)).toBe('default')
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd React && npx vitest run src/renderer/src/design-system/tokens/colorMap.test.ts`
Expected: FAIL — `chipColorFor('lightBlue')` returns `'default'` today (lightBlue has no legacy source and isn't passed through).

- [ ] **Step 3: Implement the passthrough** in `colorMap.ts`. The chip palette keys are the keys of `chipColor` — but `colorMap.ts` is runtime-pure and must NOT import `chip.css`. Hardcode the render-key set (it's the `ChipColorName` union, already the single source in `chip.css`'s type):

```typescript
// The render palette keys (mirror chip.css ChipColorName minus 'default'); listed here so the
// module stays runtime-pure (no chip.css import). A solid key is its own render key — pass through.
const PALETTE: ReadonlySet<string> = new Set([
  'red', 'orange', 'yellow', 'green', 'lightBlue', 'cyan', 'blue', 'purple', 'lavender', 'grey'
])

/** A stored option/area color → its chip palette key. A solid key passes through; a legacy Notion
 *  name maps; absent or unrecognized → the neutral default. */
export function chipColorFor(color: string | undefined): ChipColorName {
  if (color && PALETTE.has(color)) return color as ChipColorName
  return (color && MAP[color]) || 'default'
}
```

- [ ] **Step 4: Open the zod color fields** in `src/shared/properties.ts`. Change the three color fields from `selectColor` to a permissive string (keep `selectColor` exported — Phase 2's picker uses it as its swatch list, and the render read-map still needs the legacy names):

```typescript
// selectOption
color: z.string().optional()
// statusOption
color: z.string().optional()
// statusGroup — required with a sane fallback
color: z.string().catch('grey')
```

- [ ] **Step 5: Run tests to verify pass**

Run: `cd React && npx vitest run src/renderer/src/design-system/tokens/colorMap.test.ts && npx vitest run src/shared`
Expected: PASS. Then `npm run typecheck` — expected clean (the color fields are now `string`, which every reader already tolerates via `chipColorFor(string | undefined)`).

- [ ] **Step 6: Commit**

```bash
git add src/shared/properties.ts src/renderer/src/design-system/tokens/colorMap.ts src/renderer/src/design-system/tokens/colorMap.test.ts
git commit -m "feat(properties): open the option color to the solid palette (lightBlue in)"
```

---

## Task 2: Relabel the Status Seed + Legacy-Aware `isUntouchedSeed`

**Files:**
- Modify: `src/shared/properties.ts` (`defaultStatusSeed`, `defaultSelectSeed`, `isUntouchedSeed`; add `legacyStatusSeed`)
- Test: `src/shared/properties.test.ts` (add cases)

**Interfaces:**
- Produces: `defaultStatusSeed(): StatusGroup[]` now Open/Active/Done, value=title, group-colored. `isUntouchedSeed(def): boolean` — true for BOTH the new and the legacy seed.

- [ ] **Step 1: Write the failing tests** — add to `properties.test.ts`:

```typescript
import { defaultStatusSeed, isUntouchedSeed, type PropertyDefinition } from './properties'

describe('status seed relabel', () => {
  it('seeds Open/Active/Done with value=label=title and group colors', () => {
    const g = defaultStatusSeed()
    expect(g.map((x) => x.label)).toEqual(['Open', 'Active', 'Done'])
    expect(g.map((x) => x.id)).toEqual(['upcoming', 'in_progress', 'done'])
    for (const grp of g) {
      expect(grp.options).toHaveLength(1)
      expect(grp.options[0].value).toBe(grp.label)
      expect(grp.options[0].label).toBe(grp.label)
      expect(grp.options[0].color).toBe(grp.color)
    }
  })
  it('isUntouchedSeed recognizes the LEGACY seed so existing props stay empty', () => {
    const legacy = {
      id: 'prop_x', name: 'Status', type: 'status',
      status_groups: [
        { id: 'upcoming', label: 'Upcoming', color: 'gray', options: [{ value: 'not_started', label: 'Not started', group_id: 'upcoming' }] },
        { id: 'in_progress', label: 'In Progress', color: 'blue', options: [{ value: 'in_progress', label: 'In progress', color: 'blue', group_id: 'in_progress' }] },
        { id: 'done', label: 'Done', color: 'green', options: [{ value: 'done', label: 'Done', color: 'green', group_id: 'done' }] }
      ]
    } as unknown as PropertyDefinition
    expect(isUntouchedSeed(legacy)).toBe(true)
  })
  it('isUntouchedSeed recognizes the NEW seed', () => {
    expect(isUntouchedSeed({ id: 'p', name: 'S', type: 'status', status_groups: defaultStatusSeed() } as PropertyDefinition)).toBe(true)
  })
  it('a customized status def is not an untouched seed', () => {
    const g = defaultStatusSeed()
    g[0].options.push({ value: 'Blocked', label: 'Blocked', group_id: 'upcoming' })
    expect(isUntouchedSeed({ id: 'p', name: 'S', type: 'status', status_groups: g } as PropertyDefinition)).toBe(false)
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd React && npx vitest run src/shared/properties.test.ts`
Expected: FAIL — labels are Upcoming/In Progress/Done today; legacy check passes only against the current (legacy) seed, new-seed check fails.

- [ ] **Step 3: Rewrite `defaultStatusSeed` + capture the legacy seed + widen `isUntouchedSeed`**:

```typescript
export function defaultStatusSeed(): StatusGroup[] {
  return [
    { id: 'upcoming', label: 'Open', color: 'grey', options: [{ value: 'Open', label: 'Open', color: 'grey', group_id: 'upcoming' }] },
    { id: 'in_progress', label: 'Active', color: 'blue', options: [{ value: 'Active', label: 'Active', color: 'blue', group_id: 'in_progress' }] },
    { id: 'done', label: 'Done', color: 'green', options: [{ value: 'Done', label: 'Done', color: 'green', group_id: 'done' }] }
  ]
}

/** The pre-7-3 seed. A Status property untouched since before the relabel still matches this, so it
 *  keeps rendering as an empty (seed-only) def rather than surfacing its old starter options. */
function legacyStatusSeed(): StatusGroup[] {
  return [
    { id: 'upcoming', label: 'Upcoming', color: 'gray', options: [{ value: 'not_started', label: 'Not started', group_id: 'upcoming' }] },
    { id: 'in_progress', label: 'In Progress', color: 'blue', options: [{ value: 'in_progress', label: 'In progress', color: 'blue', group_id: 'in_progress' }] },
    { id: 'done', label: 'Done', color: 'green', options: [{ value: 'done', label: 'Done', color: 'green', group_id: 'done' }] }
  ]
}
```

Refactor `isUntouchedSeed`'s status branch to test against BOTH seeds (extract the per-seed matcher):

```typescript
export function isUntouchedSeed(def: PropertyDefinition): boolean {
  if (def.type === 'status') {
    const groups = def.status_groups
    if (!groups) return false
    const matches = (seed: StatusGroup[]): boolean =>
      groups.length === seed.length &&
      seed.every((sg) => {
        const g = groups.find((x) => x.id === sg.id)
        return (
          g?.options.length === 1 &&
          g.options[0].value === sg.options[0].value &&
          g.options[0].label === sg.options[0].label
        )
      })
    return matches(defaultStatusSeed()) || matches(legacyStatusSeed())
  }
  if (def.type === 'select' || def.type === 'multi_select') {
    const seed = defaultSelectSeed()[0]
    return def.select_options?.length === 1 && def.select_options[0].value === seed.value && def.select_options[0].label === seed.label
  }
  return false
}
```

Align `defaultSelectSeed` to value=title:

```typescript
export function defaultSelectSeed(): { value: string; label: string }[] {
  return [{ value: 'Option 1', label: 'Option 1' }]
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd React && npx vitest run src/shared/properties.test.ts && npm run typecheck`
Expected: PASS + clean typecheck.

- [ ] **Step 5: Commit**

```bash
git add src/shared/properties.ts src/shared/properties.test.ts
git commit -m "feat(properties): relabel status seed Open/Active/Done, value=title, legacy-aware seed check"
```

---

## Task 3: Drop the ≥1-Option Floor + the Pure Option Model

**Files:**
- Modify: `src/main/properties/schema.ts` (`validateDefinition`; add `validateOptionValues`)
- Create: `src/shared/optionModel.ts`
- Test: `src/main/properties/schema.test.ts` (add), `src/shared/optionModel.test.ts` (create)

**Interfaces:**
- Produces: `validateOptionValues(options: {value: string}[]): Result<null>` (unique values). `optionModel.ts`: `addOption`, `renameOption`, `recolorOption`, `reorderOption`, `fallbackTitle`.

- [ ] **Step 1: Write the failing tests** — `optionModel.test.ts`:

```typescript
import { describe, it, expect } from 'vitest'
import { addOption, renameOption, recolorOption, reorderOption, fallbackTitle } from './optionModel'

const opt = (t: string, color?: string) => ({ value: t, label: t, ...(color ? { color } : {}) })

describe('optionModel', () => {
  it('addOption appends a grey-default option with value=label=title', () => {
    expect(addOption([opt('A')], 'B')).toEqual([opt('A'), { value: 'B', label: 'B', color: 'grey' }])
  })
  it('fallbackTitle yields Label for select and the group name for status', () => {
    expect(fallbackTitle('select')).toBe('Label')
    expect(fallbackTitle('status', 'Active')).toBe('Active')
  })
  it('renameOption rewrites value+label together (stable identity is the OLD value)', () => {
    expect(renameOption([opt('A'), opt('B')], 'A', 'C')).toEqual([{ value: 'C', label: 'C' }, opt('B')])
  })
  it('recolorOption sets the color key; clearing removes it', () => {
    expect(recolorOption([opt('A')], 'A', 'blue')).toEqual([{ value: 'A', label: 'A', color: 'blue' }])
    expect(recolorOption([opt('A', 'blue')], 'A', undefined)).toEqual([opt('A')])
  })
  it('reorderOption moves an option to a new index', () => {
    expect(reorderOption([opt('A'), opt('B'), opt('C')], 'C', 0)).toEqual([opt('C'), opt('A'), opt('B')])
  })
})
```

And in `schema.test.ts`:

```typescript
it('validateDefinition allows a zero-option select (no floor)', () => {
  const def = { id: 'prop_x', name: 'Tags', type: 'select', select_options: [] } as unknown as PropertyDefinition
  expect(validateDefinition(def, []).ok).toBe(true)
})
it('validateOptionValues rejects duplicate titles', () => {
  expect(validateOptionValues([{ value: 'A' }, { value: 'A' }]).ok).toBe(false)
  expect(validateOptionValues([{ value: 'A' }, { value: 'B' }]).ok).toBe(true)
})
```

- [ ] **Step 2: Run to verify fail**

Run: `cd React && npx vitest run src/shared/optionModel.test.ts src/main/properties/schema.test.ts`
Expected: FAIL — `optionModel` doesn't exist; `validateDefinition([])` fails the ≥1 floor; `validateOptionValues` is undefined.

- [ ] **Step 3a: Create `src/shared/optionModel.ts`** (pure, no fs/React):

```typescript
import type { PropertyType } from './properties'

export type Option = { value: string; label: string; color?: string; group_id?: string }

/** The empty-name fallback: Select/Multi → "Label"; Status → its group's label. */
export function fallbackTitle(type: PropertyType, groupLabel?: string): string {
  return type === 'status' ? (groupLabel ?? 'Label') : 'Label'
}

/** Append a new grey-default option whose value and label both equal the title. */
export function addOption(options: Option[], title: string, groupId?: string): Option[] {
  return [...options, { value: title, label: title, color: 'grey', ...(groupId ? { group_id: groupId } : {}) }]
}

/** Rename by OLD value; value=label become the new title. Identity keys on the old value. */
export function renameOption(options: Option[], oldValue: string, title: string): Option[] {
  return options.map((o) => (o.value === oldValue ? { ...o, value: title, label: title } : o))
}

/** Set or clear an option's color key (undefined removes the field). */
export function recolorOption(options: Option[], value: string, color: string | undefined): Option[] {
  return options.map((o) => {
    if (o.value !== value) return o
    const { color: _drop, ...rest } = o
    return color ? { ...rest, color } : rest
  })
}

/** Move the option with `value` to `toIndex` (in the without-dragged coordinate space). */
export function reorderOption(options: Option[], value: string, toIndex: number): Option[] {
  const without = options.filter((o) => o.value !== value)
  const moved = options.find((o) => o.value === value)
  if (!moved) return options
  return [...without.slice(0, toIndex), moved, ...without.slice(toIndex)]
}
```

- [ ] **Step 3b: In `schema.ts`**, delete the `options.length === 0` floor and extract the unique check as `validateOptionValues`:

```typescript
export function validateOptionValues(options: { value: string }[]): Result<null> {
  const values = options.map((o) => o.value)
  if (new Set(values).size < values.length) {
    return fail('invalid-property', 'Option titles must be unique.')
  }
  return ok(null)
}
```

Then in `validateDefinition`, replace the select block body with:

```typescript
  if (def.type === 'select' || def.type === 'multi_select') {
    const check = validateOptionValues(def.select_options ?? [])
    if (!check.ok) return check
  }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd React && npx vitest run src/shared/optionModel.test.ts src/main/properties/schema.test.ts && npm run typecheck`
Expected: PASS + clean.

- [ ] **Step 5: Commit**

```bash
git add src/shared/optionModel.ts src/shared/optionModel.test.ts src/main/properties/schema.ts src/main/properties/schema.test.ts
git commit -m "feat(properties): drop the >=1-option floor; add the pure option model + unique check"
```

---

## Task 4: Per-Value Page Primitives (Strip + Replace)

**Files:**
- Create: `src/main/crud/pageValue.ts`
- Test: `src/main/crud/pageValue.test.ts`

**Interfaces:**
- Consumes: `stripPageMember` sibling patterns from `crud/schema.ts` (`splitFrontmatter`, `mergeFrontmatter`, `splitEnvelope`, `nowIso`, `isPlainObject`).
- Produces:
  - `stripPageValue(content: string, propertyId: string, value: string, type: PropertyType): string | null` — remove ONE option's value; `null` when nothing changed.
  - `replacePageValue(content: string, propertyId: string, oldValue: string, newValue: string, type: PropertyType): string | null` — the rename cascade.

Both switch on `type`: **select/status** delete or replace the key iff the stored value matches; **multi_select** filter/replace within the array, delete the key only when it empties.

- [ ] **Step 1: Write the failing tests** — `pageValue.test.ts`:

```typescript
import { describe, it, expect } from 'vitest'
import { stripPageValue, replacePageValue } from './pageValue'

const page = (props: string) => `---\nid: p1\nproperties:\n${props}---\nbody\n`

describe('stripPageValue', () => {
  it('select: deletes the key iff the value matches', () => {
    expect(stripPageValue(page('  prop_s: Urgent\n'), 'prop_s', 'Urgent', 'select')).toContain('body')
    expect(stripPageValue(page('  prop_s: Urgent\n'), 'prop_s', 'Urgent', 'select')).not.toContain('prop_s')
    expect(stripPageValue(page('  prop_s: Other\n'), 'prop_s', 'Urgent', 'select')).toBeNull()
  })
  it('status: matches the $status object', () => {
    const c = stripPageValue(page('  prop_s:\n    $status: Active\n'), 'prop_s', 'Active', 'status')
    expect(c).not.toBeNull()
    expect(c).not.toContain('$status')
  })
  it('multi_select: filters the array, deletes the key only when empty', () => {
    const kept = stripPageValue(page('  prop_m:\n    - a\n    - x\n    - b\n'), 'prop_m', 'x', 'multi_select')
    expect(kept).toContain('a')
    expect(kept).toContain('b')
    expect(kept).not.toContain('- x')
    const empty = stripPageValue(page('  prop_m:\n    - x\n'), 'prop_m', 'x', 'multi_select')
    expect(empty).not.toBeNull()
    expect(empty).not.toContain('prop_m')
  })
})

describe('replacePageValue (rename cascade)', () => {
  it('select: swaps the matching value', () => {
    expect(replacePageValue(page('  prop_s: Urgent\n'), 'prop_s', 'Urgent', 'Critical', 'select')).toContain('Critical')
  })
  it('multi_select: swaps one element in place', () => {
    const c = replacePageValue(page('  prop_m:\n    - a\n    - x\n'), 'prop_m', 'x', 'y', 'multi_select')
    expect(c).toContain('- y')
    expect(c).not.toContain('- x')
  })
  it('returns null when the page does not hold the value', () => {
    expect(replacePageValue(page('  prop_s: Other\n'), 'prop_s', 'Urgent', 'Critical', 'select')).toBeNull()
  })
})
```

- [ ] **Step 2: Run to verify fail**

Run: `cd React && npx vitest run src/main/crud/pageValue.test.ts`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `pageValue.ts`** (mirror `stripPageMember`'s frontmatter read/merge; the codec's on-disk shapes are: select = bare string, status = `{ $status }`, multi = string array):

```typescript
import type { PropertyType } from '@shared/properties'
import { splitFrontmatter } from '../readNexus'
import { splitEnvelope, mergeFrontmatter } from '../io/pageFile'
import { isPlainObject } from '@shared/guards'
import { nowIso } from '../io/time'

/** The stored value(s) for a property key, as the option `value` string(s) they contain. */
function storedValues(raw: unknown, type: PropertyType): string[] {
  if (type === 'multi_select') return Array.isArray(raw) ? raw.filter((x): x is string => typeof x === 'string') : []
  if (type === 'status') return isPlainObject(raw) && typeof raw.$status === 'string' ? [raw.$status] : []
  return typeof raw === 'string' ? [raw] : [] // select
}

/** Re-encode a filtered value set back to on-disk shape, or null to signal "delete the key". */
function encode(values: string[], type: PropertyType): unknown | null {
  if (values.length === 0) return null
  if (type === 'multi_select') return values
  if (type === 'status') return { $status: values[0] }
  return values[0] // select
}

function rewrite(content: string, propertyId: string, next: unknown | null): string {
  const props = splitFrontmatter(content).properties
  const map = isPlainObject(props) ? { ...props } : {}
  if (next === null) delete map[propertyId]
  else map[propertyId] = next
  const body = splitEnvelope(content).body
  return mergeFrontmatter(content, { properties: map, modified_at: nowIso() }, ['properties', 'modified_at'], body)
}

/** Remove one option's value from a page. Returns null if the page didn't hold it. */
export function stripPageValue(content: string, propertyId: string, value: string, type: PropertyType): string | null {
  const props = splitFrontmatter(content).properties
  const raw = isPlainObject(props) ? props[propertyId] : undefined
  const values = storedValues(raw, type)
  if (!values.includes(value)) return null
  return rewrite(content, propertyId, encode(values.filter((v) => v !== value), type))
}

/** Rename cascade: swap oldValue → newValue in place. Returns null if the page didn't hold it. */
export function replacePageValue(content: string, propertyId: string, oldValue: string, newValue: string, type: PropertyType): string | null {
  const props = splitFrontmatter(content).properties
  const raw = isPlainObject(props) ? props[propertyId] : undefined
  const values = storedValues(raw, type)
  if (!values.includes(oldValue)) return null
  return rewrite(content, propertyId, encode(values.map((v) => (v === oldValue ? newValue : v)), type))
}
```

> **Grounding note for the implementer:** confirm the exact import paths for `splitFrontmatter` (`../readNexus`), `splitEnvelope`/`mergeFrontmatter` (`../io/pageFile`), `isPlainObject`, and `nowIso` against the sibling `crud/schema.ts` imports before running — match whatever `stripPageMember` imports.

- [ ] **Step 4: Run to verify pass**

Run: `cd React && npx vitest run src/main/crud/pageValue.test.ts && npm run typecheck`
Expected: PASS + clean.

- [ ] **Step 5: Commit**

```bash
git add src/main/crud/pageValue.ts src/main/crud/pageValue.test.ts
git commit -m "feat(crud): per-value page strip + replace primitives (select/status/multi)"
```

---

## Task 5: `setOptions` — Registry-Only Option Edit (No Re-Seed)

**Files:**
- Create/extend: `src/main/crud/optionOps.ts`
- Test: `src/main/crud/optionOps.test.ts`

**Interfaces:**
- Consumes: `mutateRegistry` (`io/propertiesRegistry.ts`), `validateOptionValues` (Task 3).
- Produces: `setOptions(root: string, propertyId: string, options: Option[]): Promise<Result<null>>` — validates unique titles, writes the option array to the registry def **without** routing through `seeded()` (so an emptied array stays empty — the F2 fix).

- [ ] **Step 1: Write the failing test** — `optionOps.test.ts` (use a temp nexus dir; follow the pattern in existing `crud/*.test.ts` for `mkdtemp` + `.nexus/properties.json` seeding):

```typescript
it('setOptions writes the array verbatim and does NOT re-seed an emptied select', async () => {
  const root = await tmpNexusWith({ prop_s: { id: 'prop_s', name: 'Tags', type: 'select', select_options: [{ value: 'A', label: 'A' }] } })
  const r = await setOptions(root, 'prop_s', [])
  expect(r.ok).toBe(true)
  const def = (await readRegistry(root)).defs.prop_s
  expect(def.select_options).toEqual([]) // NOT re-seeded to [Option 1]
})
it('setOptions rejects duplicate titles', async () => {
  const root = await tmpNexusWith({ prop_s: { id: 'prop_s', name: 'Tags', type: 'select', select_options: [] } })
  const r = await setOptions(root, 'prop_s', [{ value: 'A', label: 'A' }, { value: 'A', label: 'A' }])
  expect(r.ok).toBe(false)
})
```

- [ ] **Step 2: Run to verify fail** — `npx vitest run src/main/crud/optionOps.test.ts` → FAIL (module missing).

- [ ] **Step 3: Implement `setOptions`** — note it writes the def's `select_options` (select/multi) or `status_groups` (status) directly through `mutateRegistry`, bypassing `editProperty`/`seeded()`:

```typescript
import { mutateRegistry } from '../io/propertiesRegistry'
import { validateOptionValues } from '../properties/schema'
import { ok, fail, type Result } from '@shared/result'
import type { Option } from '@shared/optionModel'

/** Replace a select/multi property's options (registry-only). Never re-seeds an emptied array. */
export function setOptions(root: string, propertyId: string, options: Option[]): Promise<Result<null>> {
  return mutateRegistry<Result<null>>(root, (registry) => {
    const current = registry.defs[propertyId]
    if (!current) return { result: fail('not-found', 'Property not found.') }
    const check = validateOptionValues(options)
    if (!check.ok) return { result: check }
    const next = { ...current, select_options: options }
    return { next: { ...registry, defs: { ...registry.defs, [propertyId]: next } }, result: ok(null) }
  })
}
```

> **Status variant:** a `setStatusGroupOptions(root, propertyId, groupId, options)` follows the same shape but replaces one group's `options` within `status_groups` — deferred to Phase 3 (no Status UI here). Phase 1 ships the select/multi `setOptions`.

- [ ] **Step 4: Run to verify pass** — `npx vitest run src/main/crud/optionOps.test.ts && npm run typecheck` → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/main/crud/optionOps.ts src/main/crud/optionOps.test.ts
git commit -m "feat(crud): setOptions — registry-only option edit, no re-seed on empty"
```

---

## Task 6: `renameOption` — Registry Edit + Page Cascade

**Files:**
- Extend: `src/main/crud/optionOps.ts`
- Test: `src/main/crud/optionOps.test.ts`

**Interfaces:**
- Consumes: `serializeSchemaOp`, `mutateRegistry`, `allCollectionFolders`, `replacePageValue` (Task 4), `SchemaTransaction`, the `deleteProperty` fan-out pattern.
- Produces: `renameOption(root, propertyId, oldValue, newTitle): Promise<Result<null>>` — sets the option's value+label to `newTitle` in the registry AND replaces `oldValue → newTitle` on every page across all collections, as one `serializeSchemaOp` unit.

- [ ] **Step 1: Write the failing test:**

```typescript
it('renameOption rewrites the def and cascades page values', async () => {
  const root = await tmpNexusWith({ prop_s: { id: 'prop_s', name: 'Tags', type: 'select', select_options: [{ value: 'Urgent', label: 'Urgent' }] } })
  await tmpPage(root, 'Col/One.md', { id: 'x1', properties: { prop_s: 'Urgent' } })
  const r = await renameOption(root, 'prop_s', 'Urgent', 'Critical')
  expect(r.ok).toBe(true)
  expect((await readRegistry(root)).defs.prop_s.select_options).toEqual([{ value: 'Critical', label: 'Critical' }])
  expect(await pageValue(root, 'Col/One.md', 'prop_s')).toBe('Critical')
})
```

- [ ] **Step 2: Run to verify fail** → FAIL (renameOption missing).

- [ ] **Step 3: Implement** — model the fan-out on `deleteInner` (walk `allCollectionFolders`, stage into a `SchemaTransaction`, commit), and do the registry edit + page cascade inside ONE `serializeSchemaOp` so they can't interleave:

```typescript
import { serializeSchemaOp } from './schemaChain'
import { allCollectionFolders } from './assignment'
import { replacePageValue } from './pageValue'
import { SchemaTransaction } from './schemaTransaction' // confirm the exact export path used by deleteProperty
import { listMarkdownFiles } from '../io/fs'            // confirm against deleteProperty's import
import { readFile } from 'node:fs/promises'
import { readRegistry, writeRegistry } from '../io/propertiesRegistry'
import { renameOption as renameInArray } from '@shared/optionModel'

export function renameOption(root: string, propertyId: string, oldValue: string, newTitle: string): Promise<Result<null>> {
  return serializeSchemaOp(async () => {
    const registry = await readRegistry(root)
    const def = registry.defs[propertyId]
    if (!def) return fail('not-found', 'Property not found.')
    const nextOptions = renameInArray(def.select_options ?? [], oldValue, newTitle)
    const check = validateOptionValues(nextOptions)
    if (!check.ok) return check
    await writeRegistry(root, { ...registry, defs: { ...registry.defs, [propertyId]: { ...def, select_options: nextOptions } } })

    const tx = new SchemaTransaction()
    for (const folder of await allCollectionFolders(root)) {
      for (const file of await listMarkdownFiles(folder)) {
        let content: string
        try { content = await readFile(file, 'utf8') } catch { continue }
        const rewritten = replacePageValue(content, propertyId, oldValue, newTitle, def.type)
        if (rewritten !== null) tx.stage(file, rewritten)
      }
    }
    await tx.commit()
    return ok(null)
  })
}
```

> **Grounding note:** `deleteProperty.ts` shows the exact `SchemaTransaction` + `listMarkdownFiles` import paths and usage — copy them verbatim; the pseudo-paths above are placeholders for whatever `deleteInner` imports.

- [ ] **Step 4: Run to verify pass** → PASS + clean typecheck.

- [ ] **Step 5: Commit**

```bash
git add src/main/crud/optionOps.ts src/main/crud/optionOps.test.ts
git commit -m "feat(crud): renameOption — registry edit + page-value cascade"
```

---

## Task 7: `removeOption` + `clearOption` — Per-Value Fan-Out

**Files:**
- Extend: `src/main/crud/optionOps.ts`
- Test: `src/main/crud/optionOps.test.ts`

**Interfaces:**
- Produces:
  - `removeOption(root, propertyId, value): Promise<Result<null>>` — delete the option from the def AND `stripPageValue` from every page, one `serializeSchemaOp`.
  - `clearOption(root, propertyId, value): Promise<Result<null>>` — `stripPageValue` from every page, keep the option.

- [ ] **Step 1: Write the failing tests:**

```typescript
it('removeOption deletes the def option and strips it from pages', async () => {
  const root = await tmpNexusWith({ prop_s: { id: 'prop_s', name: 'T', type: 'select', select_options: [{ value: 'A', label: 'A' }, { value: 'B', label: 'B' }] } })
  await tmpPage(root, 'Col/One.md', { id: 'x1', properties: { prop_s: 'A' } })
  const r = await removeOption(root, 'prop_s', 'A')
  expect(r.ok).toBe(true)
  expect((await readRegistry(root)).defs.prop_s.select_options).toEqual([{ value: 'B', label: 'B' }])
  expect(await pageValue(root, 'Col/One.md', 'prop_s')).toBeUndefined()
})
it('clearOption strips pages but KEEPS the option', async () => {
  const root = await tmpNexusWith({ prop_s: { id: 'prop_s', name: 'T', type: 'select', select_options: [{ value: 'A', label: 'A' }] } })
  await tmpPage(root, 'Col/One.md', { id: 'x1', properties: { prop_s: 'A' } })
  const r = await clearOption(root, 'prop_s', 'A')
  expect(r.ok).toBe(true)
  expect((await readRegistry(root)).defs.prop_s.select_options).toEqual([{ value: 'A', label: 'A' }])
  expect(await pageValue(root, 'Col/One.md', 'prop_s')).toBeUndefined()
})
```

- [ ] **Step 2: Run to verify fail** → FAIL.

- [ ] **Step 3: Implement** — extract a shared `stripAcrossPages(root, propertyId, value, type)` helper (the fan-out loop) that both use; `removeOption` additionally edits the def:

```typescript
async function stripAcrossPages(root: string, propertyId: string, value: string, type: PropertyType): Promise<void> {
  const tx = new SchemaTransaction()
  for (const folder of await allCollectionFolders(root)) {
    for (const file of await listMarkdownFiles(folder)) {
      let content: string
      try { content = await readFile(file, 'utf8') } catch { continue }
      const stripped = stripPageValue(content, propertyId, value, type)
      if (stripped !== null) tx.stage(file, stripped)
    }
  }
  await tx.commit()
}

export function clearOption(root: string, propertyId: string, value: string): Promise<Result<null>> {
  return serializeSchemaOp(async () => {
    const def = (await readRegistry(root)).defs[propertyId]
    if (!def) return fail('not-found', 'Property not found.')
    await stripAcrossPages(root, propertyId, value, def.type)
    return ok(null)
  })
}

export function removeOption(root: string, propertyId: string, value: string): Promise<Result<null>> {
  return serializeSchemaOp(async () => {
    const registry = await readRegistry(root)
    const def = registry.defs[propertyId]
    if (!def) return fail('not-found', 'Property not found.')
    const nextOptions = (def.select_options ?? []).filter((o) => o.value !== value)
    await writeRegistry(root, { ...registry, defs: { ...registry.defs, [propertyId]: { ...def, select_options: nextOptions } } })
    await stripAcrossPages(root, propertyId, value, def.type)
    return ok(null)
  })
}
```

- [ ] **Step 4: Run to verify pass** → PASS + clean.

- [ ] **Step 5: Commit**

```bash
git add src/main/crud/optionOps.ts src/main/crud/optionOps.test.ts
git commit -m "feat(crud): removeOption + clearOption — per-value fan-out"
```

---

## Task 8: IPC Wiring — Preload Bridge + Main Handlers

**Files:**
- Modify: `src/preload/index.ts` (the `schema` bridge block)
- Modify: `src/main/index.ts` (register four handlers)
- Test: manual smoke via the running app is Phase 2; here, `npm run typecheck` + the existing IPC-shape tests guard the envelope.

**Interfaces:**
- Consumes: `setOptions`/`renameOption`/`removeOption`/`clearOption` (Tasks 5-7), `resolveSchemaFolder` (existing), the `{ok}|{ok:false,error}` envelope.
- Produces: `window.nexus.schema.setOptions/renameOption/removeOption/clearOption`.

- [ ] **Step 1: Add the preload bridge** (in the `schema: {` block, mirroring `rename`):

```typescript
    setOptions: (
      propertyId: string,
      options: { value: string; label: string; color?: string }[]
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('schema:setOptions', propertyId, options),
    renameOption: (
      propertyId: string,
      oldValue: string,
      newTitle: string
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('schema:renameOption', propertyId, oldValue, newTitle),
    removeOption: (
      propertyId: string,
      value: string
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('schema:removeOption', propertyId, value),
    clearOption: (
      propertyId: string,
      value: string
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('schema:clearOption', propertyId, value),
```

- [ ] **Step 2: Register the main handlers** (these are registry-scoped — keyed by `propertyId`, no `containerPath`, so they use `sessionRoot()` like `property:delete`, NOT `resolveSchemaFolder`):

```typescript
ipcMain.handle('schema:setOptions', async (_e, propertyId: unknown, options: unknown): Promise<{ ok: true } | { ok: false; error: string }> => {
  try {
    const root = sessionRoot()
    if (root === null) return { ok: false, error: 'No nexus is open.' }
    if (typeof propertyId !== 'string' || !Array.isArray(options)) return { ok: false, error: 'propertyId (string) and options (array) are required.' }
    const parsed = z.array(selectOption).safeParse(options) // selectOption imported from @shared/properties
    if (!parsed.success) return { ok: false, error: 'Invalid options.' }
    const r = await setOptions(root, propertyId, parsed.data)
    return r.ok ? { ok: true } : { ok: false, error: r.error.message }
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) }
  }
})
// schema:renameOption / schema:removeOption / schema:clearOption follow the identical envelope:
// validate the string args, call the op, return { ok } | { ok:false, error }.
```

> Write out all four handlers (the three below `setOptions` are simpler — two/three string args each, no zod array parse). The pattern is verbatim `property:delete` (sessionRoot + string-guard + call + envelope).

- [ ] **Step 3: Typecheck**

Run: `cd React && npm run typecheck`
Expected: clean. `selectOption` isn't currently exported from `properties.ts` — export it if the handler needs it, or validate inline with `z.array(z.object({ value: z.string(), label: z.string(), color: z.string().optional() }))`.

- [ ] **Step 4: Full-suite gate**

Run: `cd React && npx vitest run`
Expected: all green (the new tests + no regressions).

- [ ] **Step 5: Commit**

```bash
git add src/preload/index.ts src/main/index.ts src/shared/properties.ts
git commit -m "feat(ipc): setOptions/renameOption/removeOption/clearOption bridge + handlers"
```

---

## Self-Review

**Spec coverage** (Phase 1 items in the spec → task):
- value=title + rename cascade → Tasks 3 (model), 6 (cascade). ✓
- open color key + `chipColorFor` normalizer → Task 1. ✓
- Status relabel Open/Active/Done + legacy-aware `isUntouchedSeed` → Task 2. ✓
- remove ≥1 floor + no re-seed on empty → Tasks 3 (floor), 5 (no re-seed). ✓
- pure option model → Task 3. ✓
- per-value page-strip primitive → Task 4. ✓
- `setOptions` (mutateRegistry) → Task 5. ✓
- `renameOption`/`removeOption`/`clearOption` (serializeSchemaOp) → Tasks 6-7. ✓
- IPC + confirm-dialog scoping (confirm deferred to Phase 2) → Task 8 + Global Constraints. ✓
- Status per-group `setStatusGroupOptions` → explicitly deferred to Phase 3 (Task 5 note), since no Status UI exists here to drive it. **Gap flagged, not silent.**

**Placeholder scan:** the "confirm the import path" grounding notes in Tasks 4 & 6 are deliberate — they point the implementer at the real sibling file (`crud/schema.ts` / `deleteProperty.ts`) to copy verbatim import paths, since those exact paths weren't all captured. Every code block is real, runnable code, not a stub.

**Type consistency:** `Option` (`optionModel.ts`) = `{ value; label; color?; group_id? }` used consistently across Tasks 3-7; `setOptions`/`renameOption`/`removeOption`/`clearOption` signatures match between their crud definitions (Tasks 5-7) and the preload bridge (Task 8). `chipColorFor(string | undefined): ChipColorName` matches its only new caller shape.

## Execution Handoff

Phases 2-3 (the Select/Multi pane, then the Status pane + per-group `setStatusGroupOptions` + the per-property Style store) get their own plans once Phase 1 lands green.
