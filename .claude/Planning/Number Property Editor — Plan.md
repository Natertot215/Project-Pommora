# Number Property Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the `number` property a property-wide Format editor (family · currency · separators · decimals · fraction "out of" Value) plus a per-view Number/Bar look that renders an in-cell progress bar.

**Architecture:** Number *format* config becomes **def-level** fields on `PropertyDefinition` (mirroring `checkbox_color`/`link_color`), written through one batched IPC handler. The per-view *look* stays in `column_styles.look` (mirroring checkbox's color-def/look-view split). The existing per-view `number_format` enum is removed and its column-menu radios repurposed to Number/Bar. `formatNumber` is rewritten to read the def config; a new `ProgressBar` design-system component renders the bar.

**Tech Stack:** Electron 42 · React 19 · TypeScript 6 · zod · vanilla-extract CSS · Vitest · `Intl.NumberFormat`.

## Global Constraints

- **Spec:** `.claude/Planning/Number Property Editor — Decision Log.md` (review-certified). This plan builds from it.
- **Field names** (def-level, on `propertyDefinition`): `number_family`, `number_currency`, `number_separators`, `number_decimals`, `number_fraction`, `number_denominator`. **Never reuse `number_format`** — that name is Swift's def-level foreign key preserved in `build.ts:187 configOf`; a collision corrupts the config blob.
- **Percent stores the LITERAL** (`30` → `"30%"`), never `Intl` `style:'percent'` (which ×100s).
- **Separators** offered for Number + Currency only (row hidden for Percent). **Decimals** apply to all families.
- **Bar:** accent fill (`var(--accent)`) over a label-control track, **no stroke** (Nathan eyeballs later), fill = `value ÷ divisor` clamped `[0,1]`.
- **Colors** from `design-system/tokens` only — never `rgb()`/`rgba()`, never a raw hex in a component.
- **Gates:** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (two `tsc` passes) + `npx vitest run <file>` + `env -u ELECTRON_RUN_AS_NODE npm run build`. **Never run Biome** — it auto-formats on write; if an Edit fails on whitespace, re-read and retry.
- **Never** launch the GUI in this flow; verification is typecheck + vitest + build. Build-time visual eyeball items (leave as-is, flag for Nathan): Decimals "Hidden" exact semantics, fraction wording "N out of M" vs "N/M", bar clamp at edges, bar strokeless look, bar height/centering.
- **Commit** after each task. End every commit message with:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- **Branch:** work on a `number-property-editor` branch off `main` (not on `main`).

---

### Task 1: Def-level number fields on the schema

**Files:**
- Modify: `src/shared/properties.ts` (add fields to `propertyDefinition`, ~line 91 after `checkbox_color`; add exported consts/types near `propertyType`)
- Test: `src/shared/properties.test.ts`

**Interfaces:**
- Produces: `NUMBER_FAMILIES`, `NumberFamily`, `CURRENCY_CODES`, `NumberConfig` (a `Pick` of the six def fields); the six new optional keys on `PropertyDefinition`.

- [ ] **Step 1: Write the failing test**

Add to `src/shared/properties.test.ts` inside `describe('propertyDefinition', …)`:

```typescript
it('round-trips a number def with its property-wide format config', () => {
  const def = {
    id: 'prop_n',
    name: 'Progress',
    type: 'number',
    number_family: 'currency',
    number_currency: 'GBP',
    number_separators: true,
    number_decimals: 2,
    number_fraction: true,
    number_denominator: 100
  }
  expect(propertyDefinition.parse(def)).toEqual(def)
})

it('drops a non-string number_family to undefined rather than failing the def', () => {
  const parsed = propertyDefinition.parse({ id: 'p', name: 'x', type: 'number', number_family: 9 })
  expect(parsed.number_family).toBeUndefined()
})

it('accepts number_decimals as the literal "hidden" or an integer', () => {
  expect(propertyDefinition.parse({ id: 'p', name: 'x', type: 'number', number_decimals: 'hidden' }).number_decimals).toBe('hidden')
  expect(propertyDefinition.parse({ id: 'p', name: 'x', type: 'number', number_decimals: 3 }).number_decimals).toBe(3)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Pommora && npx vitest run src/shared/properties.test.ts`
Expected: FAIL — number fields stripped (loose object drops them; `toEqual` mismatch).

- [ ] **Step 3: Add the consts, types, and zod fields**

In `src/shared/properties.ts`, after the `propertyType` block (~line 29) add:

```typescript
/** Number format families. `number` = plain, `percent` = literal + `%` (NOT ×100), `currency` = an ISO code. */
export const NUMBER_FAMILIES = ['number', 'percent', 'currency'] as const
export type NumberFamily = (typeof NUMBER_FAMILIES)[number]

/** The currencies seeded in the Format picker; `Intl.NumberFormat` renders any ISO code, so this is
 *  the curated common set, not a limit. */
export const CURRENCY_CODES = ['USD', 'EUR', 'GBP', 'AUD', 'CAD', 'JPY'] as const
```

Inside `propertyDefinition` (the `z.looseObject({ … })`), after `checkbox_color` (~line 91) add:

```typescript
  // Def-level (property-wide) number format config — a deliberate divergence from Swift, whose number
  // format rode per-def as the inert `number_format` foreign key (still preserved in build.ts's config
  // blob). These are READ by the renderer. `number_family` picks plain/percent/currency; percent stores
  // the LITERAL (30 → "30%"); `number_decimals` is 'hidden' (no places shown) or a fixed 1–10; fraction
  // renders "N out of number_denominator" (Number/Currency only). Loose .catch ⇒ a bad value drops the
  // field, never the def.
  number_family: z.enum(NUMBER_FAMILIES).optional().catch(undefined),
  number_currency: z.string().optional().catch(undefined),
  number_separators: z.boolean().optional().catch(undefined),
  number_decimals: z.union([z.literal('hidden'), z.number().int()]).optional().catch(undefined),
  number_fraction: z.boolean().optional().catch(undefined),
  number_denominator: z.number().optional().catch(undefined)
```

After the `PropertyDefinition` type export (~line 93) add:

```typescript
/** The def-level number format config, narrowed for the pure formatter + the editor. */
export type NumberConfig = Pick<
  PropertyDefinition,
  'number_family' | 'number_currency' | 'number_separators' | 'number_decimals' | 'number_fraction' | 'number_denominator'
>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Pommora && npx vitest run src/shared/properties.test.ts`
Expected: PASS.

- [ ] **Step 5: Typecheck + commit**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck`
Expected: exit 0.

```bash
git add "Pommora/src/shared/properties.ts" "Pommora/src/shared/properties.test.ts"
git commit -m "feat(properties): def-level number format fields + NumberConfig"
```

---

### Task 2: Add Number/Bar to the column-look union

**Files:**
- Modify: `src/shared/columnStyles.ts:6` (`COLUMN_LOOKS`)
- Test: `src/shared/columnStyles.test.ts`

**Interfaces:**
- Produces: `'number'` and `'bar'` as valid `ColumnLook` members; `STYLE_VALUES.look` (which is `COLUMN_LOOKS`) auto-covers them.

**Note:** Additive — `number_format` and `defaultStyleFor('number')` are untouched here (removed in Task 5), so nothing breaks.

- [ ] **Step 1: Write the failing test**

Add to `src/shared/columnStyles.test.ts` (create the `describe` if the file has none for looks):

```typescript
import { COLUMN_LOOKS, columnStyle } from './columnStyles'

describe('COLUMN_LOOKS', () => {
  it('includes the number looks', () => {
    expect(COLUMN_LOOKS).toContain('number')
    expect(COLUMN_LOOKS).toContain('bar')
  })
  it('parses a bar look on a column style', () => {
    expect(columnStyle.parse({ look: 'bar' }).look).toBe('bar')
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Pommora && npx vitest run src/shared/columnStyles.test.ts`
Expected: FAIL — `'number'`/`'bar'` absent; `columnStyle.parse({look:'bar'})` drops it (`.catch(undefined)`).

- [ ] **Step 3: Add the looks**

`src/shared/columnStyles.ts:6` — replace:

```typescript
export const COLUMN_LOOKS = ['pill', 'capsule', 'checkbox', 'switch', 'title', 'full', 'filename', 'path'] as const
```

with:

```typescript
export const COLUMN_LOOKS = ['pill', 'capsule', 'checkbox', 'switch', 'title', 'full', 'filename', 'path', 'number', 'bar'] as const
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Pommora && npx vitest run src/shared/columnStyles.test.ts`
Expected: PASS.

- [ ] **Step 5: Typecheck + commit**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck`
Expected: exit 0.

```bash
git add "Pommora/src/shared/columnStyles.ts" "Pommora/src/shared/columnStyles.test.ts"
git commit -m "feat(columnStyles): add number/bar to COLUMN_LOOKS"
```

---

### Task 3: The ProgressBar design-system component

**Files:**
- Create: `src/renderer/src/design-system/components/ProgressBar/ProgressBar.tsx`
- Create: `src/renderer/src/design-system/components/ProgressBar/progressBar.css.ts`
- Test: `src/renderer/src/design-system/components/ProgressBar/ProgressBar.test.tsx`

**Interfaces:**
- Produces: `ProgressBar({ fill: number })` — clamps `fill` to `[0, 1]` (non-finite → 0) and draws an accent bar over a label-control track.

- [ ] **Step 1: Write the failing test**

Create `src/renderer/src/design-system/components/ProgressBar/ProgressBar.test.tsx`:

```tsx
import { describe, it, expect, afterEach } from 'vitest'
import { render, cleanup } from '@testing-library/react'
import { ProgressBar } from './ProgressBar'

afterEach(cleanup)

const widthOf = (c: HTMLElement): string => (c.querySelector('[role="progressbar"] > *') as HTMLElement).style.width

describe('ProgressBar', () => {
  it('maps a mid fill to a percent width', () => {
    expect(widthOf(render(<ProgressBar fill={0.3} />).container)).toBe('30%')
  })
  it('clamps over-1 to 100% and negative to 0%', () => {
    expect(widthOf(render(<ProgressBar fill={1.5} />).container)).toBe('100%')
    expect(widthOf(render(<ProgressBar fill={-1} />).container)).toBe('0%')
  })
  it('treats a non-finite fill as 0%', () => {
    expect(widthOf(render(<ProgressBar fill={Number.NaN} />).container)).toBe('0%')
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Pommora && npx vitest run src/renderer/src/design-system/components/ProgressBar/ProgressBar.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the component + styles**

Create `src/renderer/src/design-system/components/ProgressBar/progressBar.css.ts`:

```typescript
import { style } from '@vanilla-extract/css'
import { vars } from '../../tokens/color.css'

/** The unfilled track — a thin rounded bar in the label-control fill. No stroke (held for Nathan's eyeball). */
export const track = style({
  width: '100%',
  height: '6px',
  borderRadius: '999px',
  background: vars.color.label.control,
  overflow: 'hidden'
})

/** The filled portion — the runtime accent, width-driven. */
export const fill = style({
  height: '100%',
  borderRadius: '999px',
  background: 'var(--accent)'
})
```

Create `src/renderer/src/design-system/components/ProgressBar/ProgressBar.tsx`:

```tsx
import * as s from './progressBar.css'

/** A rounded progress bar — accent fill over a label-control track. `fill` is a 0–1 ratio (clamped;
 *  non-finite → 0). No numeric label, no stroke — the strokeless look is Nathan's to confirm. */
export function ProgressBar({ fill }: { fill: number }): React.JSX.Element {
  const pct = Math.max(0, Math.min(1, Number.isFinite(fill) ? fill : 0)) * 100
  return (
    <div className={s.track} role="progressbar" aria-valuenow={Math.round(pct)} aria-valuemin={0} aria-valuemax={100}>
      <div className={s.fill} style={{ width: `${pct}%` }} />
    </div>
  )
}
```

**Verify the token path first:** open `src/renderer/src/design-system/tokens/color.css.ts` and confirm the label-control accessor is `vars.color.label.control` (the path `settingsPane.css.ts` reaches via `colorVars.color.label.control`). If the export name differs, match it — do not hardcode a hex.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Pommora && npx vitest run src/renderer/src/design-system/components/ProgressBar/ProgressBar.test.tsx`
Expected: PASS.

- [ ] **Step 5: Typecheck + commit**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck`
Expected: exit 0.

```bash
git add "Pommora/src/renderer/src/design-system/components/ProgressBar/"
git commit -m "feat(design-system): ProgressBar component (accent fill, label-control track)"
```

---

### Task 4: Rewrite formatNumber + wire the Cell number branch

**Files:**
- Modify: `src/renderer/src/Detail/Views/PropertyEditing/formatValue.ts` (rewrite `formatNumber`, add `numberDivisor`, drop the `NumberFormat` import)
- Modify: `src/renderer/src/Detail/Views/Table/Cell.tsx:14` (import) + `:152-153` (number branch)
- Modify: `src/renderer/src/Detail/Views/Table/Table.css` (add `.cell-bar` wrapper rule)
- Test: `src/renderer/src/Detail/Views/PropertyEditing/formatValue.test.ts`, `src/renderer/src/Detail/Views/Table/Cell.test.tsx`

**Interfaces:**
- Consumes: `NumberConfig` (Task 1); `ProgressBar` (Task 3); `'bar'`/`'number'` looks (Task 2).
- Produces: `formatNumber(n: number, cfg: NumberConfig | undefined): string`; `numberDivisor(cfg: NumberConfig | undefined): number | undefined`.

- [ ] **Step 1: Write the failing formatter tests**

In `src/renderer/src/Detail/Views/PropertyEditing/formatValue.test.ts`, replace the existing `formatNumber` tests (they use the old enum signature) with:

```typescript
import { formatNumber, numberDivisor } from './formatValue'

describe('formatNumber', () => {
  it('groups by default and honours separators off', () => {
    expect(formatNumber(1234.5, { number_family: 'number', number_separators: true })).toBe('1,234.5')
    expect(formatNumber(1234.5, { number_family: 'number', number_separators: false })).toBe('1234.5')
  })
  it('hidden decimals show as an integer; a fixed count pads', () => {
    expect(formatNumber(3.14, { number_decimals: 'hidden' })).toBe('3')
    expect(formatNumber(3, { number_decimals: 2 })).toBe('3.00')
  })
  it('percent is literal + "%", never ×100', () => {
    expect(formatNumber(30, { number_family: 'percent' })).toBe('30%')
  })
  it('currency uses the chosen ISO code', () => {
    expect(formatNumber(1234, { number_family: 'currency', number_currency: 'GBP', number_decimals: 2 })).toBe('£1,234.00')
  })
  it('fraction renders "N out of Value"', () => {
    expect(formatNumber(3, { number_family: 'number', number_fraction: true, number_denominator: 10 })).toBe('3 out of 10')
  })
})

describe('numberDivisor', () => {
  it('is 100 for percent, the denominator for fraction, undefined otherwise', () => {
    expect(numberDivisor({ number_family: 'percent' })).toBe(100)
    expect(numberDivisor({ number_family: 'number', number_fraction: true, number_denominator: 10 })).toBe(10)
    expect(numberDivisor({ number_family: 'number', number_fraction: false })).toBeUndefined()
  })
  it('guards a zero / missing denominator', () => {
    expect(numberDivisor({ number_family: 'number', number_fraction: true, number_denominator: 0 })).toBeUndefined()
    expect(numberDivisor({ number_family: 'number', number_fraction: true })).toBeUndefined()
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Pommora && npx vitest run src/renderer/src/Detail/Views/PropertyEditing/formatValue.test.ts`
Expected: FAIL — `numberDivisor` undefined; `formatNumber` old signature.

- [ ] **Step 3: Rewrite formatNumber + add numberDivisor**

In `src/renderer/src/Detail/Views/PropertyEditing/formatValue.ts`:

Change the import at line 5 from:

```typescript
import type { DateFormat, NumberFormat, TimeFormat, WeekdayFormat } from '@shared/columnStyles'
```

to:

```typescript
import type { DateFormat, TimeFormat, WeekdayFormat } from '@shared/columnStyles'
import type { NumberConfig } from '@shared/properties'
```

Replace the whole `formatNumber` block (lines 116-129) with:

```typescript
/** Fraction-option digit settings for `Intl` — 'hidden' shows no places, a fixed count pins min=max,
 *  absent shows the number's natural decimals (Intl default). */
function fractionDigits(decimals: NumberConfig['number_decimals']): Intl.NumberFormatOptions {
  if (decimals === 'hidden') return { maximumFractionDigits: 0 }
  if (typeof decimals === 'number') return { minimumFractionDigits: decimals, maximumFractionDigits: decimals }
  return {}
}

/** One scalar formatted by the family (no fraction wrapping). Percent is LITERAL — the number plus '%',
 *  never Intl's ×100 percent style. Currency uses the chosen ISO code (default USD). */
function formatScalar(n: number, cfg: NumberConfig | undefined): string {
  const useGrouping = cfg?.number_separators !== false
  const digits = fractionDigits(cfg?.number_decimals)
  if (cfg?.number_family === 'currency') {
    return new Intl.NumberFormat('en-US', { style: 'currency', currency: cfg.number_currency ?? 'USD', useGrouping, ...digits }).format(n)
  }
  const num = new Intl.NumberFormat('en-US', { useGrouping, ...digits }).format(n)
  return cfg?.number_family === 'percent' ? `${num}%` : num
}

/** Render a number per its def-level config. Fraction (Number/Currency) wraps the scalar as
 *  "N out of Value"; every other case is the bare scalar. */
export function formatNumber(n: number, cfg: NumberConfig | undefined): string {
  if (cfg?.number_fraction && cfg.number_family !== 'percent' && cfg.number_denominator !== undefined) {
    return `${formatScalar(n, cfg)} out of ${formatScalar(cfg.number_denominator, cfg)}`
  }
  return formatScalar(n, cfg)
}

/** The bar's divisor: 100 for percent, the fraction denominator for Number/Currency, else undefined
 *  (no bar). A zero / missing denominator returns undefined so the bar never divides by zero. */
export function numberDivisor(cfg: NumberConfig | undefined): number | undefined {
  if (cfg?.number_family === 'percent') return 100
  if (cfg?.number_fraction && cfg.number_denominator) return cfg.number_denominator
  return undefined
}
```

- [ ] **Step 4: Run to verify the formatter passes**

Run: `cd Pommora && npx vitest run src/renderer/src/Detail/Views/PropertyEditing/formatValue.test.ts`
Expected: PASS.

- [ ] **Step 5: Wire the Cell number branch**

In `src/renderer/src/Detail/Views/Table/Cell.tsx`, line 14, add `numberDivisor` to the import and add `ProgressBar`:

```typescript
import { fileLabel, formatDate, formatNumber, numberDivisor } from '../PropertyEditing/formatValue'
```

Add near the other component imports (after line 8):

```typescript
import { ProgressBar } from '@renderer/design-system/components/ProgressBar/ProgressBar'
```

Replace the number branch (lines 152-153):

```typescript
    case 'number':
      return <OverflowScroll className="cell-text-scroll">{formatNumber(v.value, style.number_format ?? 'decimal')}</OverflowScroll>
```

with:

```typescript
    case 'number': {
      const def = ctx.schema.find((d) => d.id === column.id)
      const divisor = numberDivisor(def)
      if (style.look === 'bar' && divisor !== undefined) {
        return (
          <span className="cell-bar">
            <ProgressBar fill={v.value / divisor} />
          </span>
        )
      }
      return <OverflowScroll className="cell-text-scroll">{formatNumber(v.value, def)}</OverflowScroll>
    }
```

In `src/renderer/src/Detail/Views/Table/Table.css`, add (near the `.cell-switch` rule):

```css
.cell-bar {
  display: flex;
  align-items: center;
  width: 100%;
  height: 100%;
}
```

- [ ] **Step 6: Update the Cell test + run both**

In `src/renderer/src/Detail/Views/Table/Cell.test.tsx` (~line 164), the number-cell test renders with `number_format: 'percent'` on the style. Update it to the new model: a percent number now comes from the DEF, not the per-view style. Change that test's schema def to carry `number_family: 'percent'` and drop `number_format` from the style, asserting the cell text is the literal + `%` (e.g. a value of `30` → `'30%'`). Then:

Run: `cd Pommora && npx vitest run src/renderer/src/Detail/Views/Table/Cell.test.tsx src/renderer/src/Detail/Views/PropertyEditing/formatValue.test.ts`
Expected: PASS.

- [ ] **Step 7: Typecheck + commit**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck`
Expected: exit 0. (If `Cell.tsx` still references `style.number_format` anywhere else, this catches it — there should be none.)

```bash
git add "Pommora/src/renderer/src/Detail/Views/PropertyEditing/formatValue.ts" "Pommora/src/renderer/src/Detail/Views/PropertyEditing/formatValue.test.ts" "Pommora/src/renderer/src/Detail/Views/Table/Cell.tsx" "Pommora/src/renderer/src/Detail/Views/Table/Cell.test.tsx" "Pommora/src/renderer/src/Detail/Views/Table/Table.css"
git commit -m "feat(number): def-driven formatNumber + numberDivisor + bar cell render"
```

---

### Task 5: Remove the per-view number_format enum; repurpose the menu to Number/Bar

**Files:**
- Modify: `src/shared/columnStyles.ts` (drop `NUMBER_FORMATS`/`NumberFormat` lines 18-19; drop `number_format` from `columnStyle` line 28; `defaultStyleFor('number')` → `{ look: 'number' }` line 47-48)
- Modify: `src/shared/columnMenu.ts` (drop `NUMBER_FORMATS` import + `STYLE_VALUES.number_format`; rewrite `styleMenuItems` `case 'number'` to look radios)
- Test: `src/shared/columnStyles.test.ts`, `src/shared/columnMenu.test.ts`, `src/renderer/src/Detail/Views/Table/cellMenu.test.ts`

**Interfaces:**
- Consumes: the `'number'`/`'bar'` looks (Task 2).
- Produces: `styleMenuItems({type:'number', …})` → `[{key:'look',value:'number'}, {key:'look',value:'bar'}]`; `defaultStyleFor('number')` → `{ look: 'number' }`.

- [ ] **Step 1: Write the failing tests**

In `src/shared/columnStyles.test.ts` add:

```typescript
import { defaultStyleFor } from './columnStyles'

it("defaultStyleFor('number') is the number look", () => {
  expect(defaultStyleFor('number')).toEqual({ look: 'number' })
})
```

In `src/shared/columnMenu.test.ts` add (and delete any existing assertion expecting Integer/Decimal/Percent/Currency for number):

```typescript
import { styleMenuItems } from './columnMenu'

it('number style items are the Number/Bar look radios', () => {
  const items = styleMenuItems({ type: 'number', current: { look: 'bar' } })
  expect(items.map((i) => [i.label, i.key, i.value, i.checked])).toEqual([
    ['Number', 'look', 'number', false],
    ['Bar', 'look', 'bar', true]
  ])
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd Pommora && npx vitest run src/shared/columnStyles.test.ts src/shared/columnMenu.test.ts`
Expected: FAIL — `defaultStyleFor('number')` still `{number_format:'decimal'}`; number menu still the format radios.

- [ ] **Step 3: Strip number_format from columnStyles**

`src/shared/columnStyles.ts` — delete lines 18-19:

```typescript
export const NUMBER_FORMATS = ['integer', 'decimal', 'percent', 'currency'] as const
export type NumberFormat = (typeof NUMBER_FORMATS)[number]
```

Delete the `number_format` field from `columnStyle` (line 28) — remove the trailing comma juggling so the object stays valid:

```typescript
export const columnStyle = z.looseObject({
  look: z.enum(COLUMN_LOOKS).optional().catch(undefined),
  date_format: z.enum(DATE_FORMATS).optional().catch(undefined),
  time_format: z.enum(TIME_FORMATS).optional().catch(undefined),
  weekday: z.enum(WEEKDAY_FORMATS).optional().catch(undefined)
})
```

Change `defaultStyleFor` (lines 47-48):

```typescript
    case 'number':
      return { look: 'number' }
```

- [ ] **Step 4: Repurpose the number menu**

`src/shared/columnMenu.ts` — line 1, drop `NUMBER_FORMATS` from the import:

```typescript
import { COLUMN_LOOKS, DATE_FORMATS, TIME_FORMATS, WEEKDAY_FORMATS, type ColumnStyle } from './columnStyles'
```

Replace the `case 'number'` block (lines 64-67) with:

```typescript
    case 'number':
      return [look('Number', 'number'), look('Bar', 'bar')]
```

Delete `number_format: NUMBER_FORMATS` from `STYLE_VALUES` (line 97) so it reads:

```typescript
const STYLE_VALUES: Record<string, readonly string[]> = {
  look: COLUMN_LOOKS,
  date_format: DATE_FORMATS,
  time_format: TIME_FORMATS,
  weekday: WEEKDAY_FORMATS
}
```

- [ ] **Step 5: Fix the cellMenu test**

`src/renderer/src/Detail/Views/Table/cellMenu.test.ts` (~line 17) asserts a number `style-only` menu built from `number_format`. Update its expectation to the Number/Bar look items (the menu is still `style-only` for number — only the items changed). Run:

Run: `cd Pommora && npx vitest run src/shared/columnStyles.test.ts src/shared/columnMenu.test.ts src/renderer/src/Detail/Views/Table/cellMenu.test.ts`
Expected: PASS.

- [ ] **Step 6: Full typecheck + vitest sweep**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck && npx vitest run`
Expected: exit 0, all green. (Typecheck catches any remaining `NumberFormat`/`number_format` reference anywhere in the tree — there should be none outside `build.ts:187`'s dynamic string access, which is untyped and unaffected.)

- [ ] **Step 7: Commit**

```bash
git add "Pommora/src/shared/columnStyles.ts" "Pommora/src/shared/columnStyles.test.ts" "Pommora/src/shared/columnMenu.ts" "Pommora/src/shared/columnMenu.test.ts" "Pommora/src/renderer/src/Detail/Views/Table/cellMenu.test.ts"
git commit -m "refactor(number): drop per-view number_format, repurpose menu to Number/Bar look"
```

---

### Task 6: The batched IPC writer (main + preload)

**Files:**
- Modify: `src/main/index.ts` (add `property:setNumberFormat` handler after `setCheckboxColor`, ~line 785)
- Modify: `src/preload/index.ts` (add `setNumberFormat` after `setCheckboxColor`, ~line 162)

**Interfaces:**
- Produces: `window.nexus.property.setNumberFormat(propertyId, patch)` → `{ ok: true } | { ok: false; error }`, whitelisting the six number fields.

- [ ] **Step 1: Add the main handler**

In `src/main/index.ts`, after the `property:setCheckboxColor` handler (ends ~line 785), add:

```typescript
ipcMain.handle(
  'property:setNumberFormat',
  async (_e, propertyId: unknown, patch: unknown): Promise<{ ok: true } | { ok: false; error: string }> => {
    try {
      const root = sessionRoot()
      if (root === null) return { ok: false, error: 'No nexus is open.' }
      if (typeof propertyId !== 'string') return { ok: false, error: 'A property id is required.' }
      if (patch === null || typeof patch !== 'object') return { ok: false, error: 'A config patch is required.' }
      // Whitelist ONLY the number format fields — a config write must not patch arbitrary def fields
      // (type, options, id). Registry-only: display config never touches page values. An 'in p' check
      // lets a caller clear a field by passing undefined.
      const p = patch as Record<string, unknown>
      const changes: Record<string, unknown> = {}
      if ('number_family' in p) changes.number_family = typeof p.number_family === 'string' ? p.number_family : undefined
      if ('number_currency' in p) changes.number_currency = typeof p.number_currency === 'string' ? p.number_currency : undefined
      if ('number_separators' in p) changes.number_separators = typeof p.number_separators === 'boolean' ? p.number_separators : undefined
      if ('number_decimals' in p)
        changes.number_decimals = p.number_decimals === 'hidden' || typeof p.number_decimals === 'number' ? p.number_decimals : undefined
      if ('number_fraction' in p) changes.number_fraction = typeof p.number_fraction === 'boolean' ? p.number_fraction : undefined
      if ('number_denominator' in p) changes.number_denominator = typeof p.number_denominator === 'number' ? p.number_denominator : undefined
      const r = await editProperty(root, propertyId, changes)
      return r.ok ? { ok: true } : { ok: false, error: r.error.message }
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) }
    }
  }
)
```

- [ ] **Step 2: Add the preload bridge**

In `src/preload/index.ts`, after the `setCheckboxColor` method (ends ~line 162), add:

```typescript
    // Registry-only display config for a Number property: its property-wide format fields.
    setNumberFormat: (
      propertyId: string,
      patch: {
        number_family?: 'number' | 'percent' | 'currency'
        number_currency?: string
        number_separators?: boolean
        number_decimals?: 'hidden' | number
        number_fraction?: boolean
        number_denominator?: number
      }
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:setNumberFormat', propertyId, patch),
```

**Note:** the renderer's `window.nexus` type comes from the preload's inferred shape (or a `.d.ts` mirror). If the project keeps an explicit `window.nexus` type declaration (search `setCheckboxColor` in `src/renderer` / a `preload.d.ts`), add `setNumberFormat` there in the same shape.

- [ ] **Step 3: Typecheck**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck`
Expected: exit 0. (main + preload changes don't hot-reload; a running dev process needs a restart — not relevant to the gate.)

- [ ] **Step 4: Commit**

```bash
git add "Pommora/src/main/index.ts" "Pommora/src/preload/index.ts"
git commit -m "feat(ipc): property:setNumberFormat batched def writer"
```

---

### Task 7: The NumberEditor pane + PropertiesPane wiring

**Files:**
- Create: `src/renderer/src/Components/Detail/NumberEditor.tsx`
- Create: `src/renderer/src/Components/Detail/numberEditor.css.ts`
- Modify: `src/renderer/src/Components/Detail/PropertiesPane.tsx` (add `saveNumberFormat` ~line 256; add the `def.type === 'number'` branch ~line 398)
- Test: `src/renderer/src/Components/Detail/NumberEditor.test.tsx`

**Interfaces:**
- Consumes: `NumberConfig`, `NUMBER_FAMILIES`, `CURRENCY_CODES` (Task 1); `PickerControl` / `PickerChoice`; `Reveal`; `Switch`; the `configEditor`/`configRow`/`configLabel`/`switchScale`/`optionsLabel` styles.
- Produces: `NumberEditor({ config, look, onSetConfig, onSetStyle })`.

- [ ] **Step 1: Write the failing test**

Create `src/renderer/src/Components/Detail/NumberEditor.test.tsx`:

```tsx
import { describe, it, expect, vi, afterEach } from 'vitest'
import { render, screen, cleanup } from '@testing-library/react'
import { NumberEditor } from './NumberEditor'

afterEach(cleanup)

describe('NumberEditor', () => {
  it('shows the Currency row only when the family is currency', () => {
    const { rerender } = render(<NumberEditor config={{ number_family: 'number' }} look="number" onSetConfig={vi.fn()} onSetStyle={vi.fn()} />)
    expect(screen.queryByText('Currency')).toBeNull()
    rerender(<NumberEditor config={{ number_family: 'currency' }} look="number" onSetConfig={vi.fn()} onSetStyle={vi.fn()} />)
    expect(screen.getByText('Currency')).toBeTruthy()
  })

  it('hides Separators + Fraction for percent and shows the Style row', () => {
    render(<NumberEditor config={{ number_family: 'percent' }} look="number" onSetConfig={vi.fn()} onSetStyle={vi.fn()} />)
    expect(screen.queryByText('Separators')).toBeNull()
    expect(screen.queryByText('Fraction')).toBeNull()
    expect(screen.getByText('Style')).toBeTruthy()
  })

  it('reveals the Value row only when fraction is on', () => {
    const { rerender } = render(<NumberEditor config={{ number_family: 'number', number_fraction: false }} look="number" onSetConfig={vi.fn()} onSetStyle={vi.fn()} />)
    expect(screen.queryByText('Value')).toBeNull()
    rerender(<NumberEditor config={{ number_family: 'number', number_fraction: true, number_denominator: 10 }} look="number" onSetConfig={vi.fn()} onSetStyle={vi.fn()} />)
    expect(screen.getByText('Value')).toBeTruthy()
  })
})
```

**Note on `Reveal`:** it mounts children on `open` and unmounts on collapse, so a hidden row's label is genuinely absent from the DOM — `queryByText(...)` returning null is the correct assertion for a closed row.

- [ ] **Step 2: Run to verify it fails**

Run: `cd Pommora && npx vitest run src/renderer/src/Components/Detail/NumberEditor.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the css**

Create `src/renderer/src/Components/Detail/numberEditor.css.ts`:

```typescript
import { style } from '@vanilla-extract/css'
import { vars as colorVars, inputFieldVar } from '../../design-system/tokens/color.css'
import { text } from '../../design-system/tokens/typography.css'

/** The Value (denominator) numeric input — a small right-aligned field in the config row, the
 *  input-field fill, the control label tone. */
export const valueInput = style([
  text.control.emphasized,
  {
    width: '64px',
    textAlign: 'right',
    background: inputFieldVar,
    border: 'none',
    outline: 'none',
    borderRadius: '6px',
    padding: '2px 6px',
    color: colorVars.color.label.control,
    font: 'inherit'
  }
])
```

**Verify** `inputFieldVar` is exported from `tokens/color.css` (it is — `settingsPane.css.ts:2` imports it). If not, use `colorVars.color.fill.quaternary` or the accessor the icon button uses.

- [ ] **Step 4: Write the component**

Create `src/renderer/src/Components/Detail/NumberEditor.tsx`:

```tsx
import type { NumberConfig, NumberFamily } from '@shared/properties'
import { CURRENCY_CODES } from '@shared/properties'
import { Switch } from '@renderer/design-system/components/Switches/Switch'
import { PickerControl, type PickerChoice } from './PickerControl'
import { Reveal } from '../../design-system/components/Reveal'
import { configEditor, configRow, configLabel, switchScale, optionsLabel } from './settingsPane.css'
import * as s from './numberEditor.css'

export type NumberLook = 'number' | 'bar'

const FAMILY_OPTIONS: PickerChoice<NumberFamily>[] = [
  { value: 'number', label: 'Number' },
  { value: 'percent', label: 'Percent' },
  { value: 'currency', label: 'Currency' }
]
const CURRENCY_OPTIONS: PickerChoice<string>[] = CURRENCY_CODES.map((c) => ({ value: c, label: c }))
const STYLE_OPTIONS: PickerChoice<NumberLook>[] = [
  { value: 'number', label: 'Number' },
  { value: 'bar', label: 'Bar' }
]
// 'hidden' + 1..10, all as picker strings (PickerControl is <T extends string>).
const DECIMAL_OPTIONS: PickerChoice<string>[] = [
  { value: 'hidden', label: 'Hidden' },
  ...Array.from({ length: 10 }, (_, i) => ({ value: String(i + 1), label: String(i + 1) }))
]

const decimalsToPicker = (d: NumberConfig['number_decimals']): string => (d === 'hidden' ? 'hidden' : typeof d === 'number' ? String(d) : 'hidden')
const pickerToDecimals = (v: string): 'hidden' | number => (v === 'hidden' ? 'hidden' : Number(v))

/** The Number property editor — property-wide Format config (Family · conditional Currency · Separators ·
 *  Decimals · conditional Fraction + Value) plus a per-view Style row (Number/Bar). Def-level fields
 *  write `onSetConfig` (the batched IPC); the look writes `onSetStyle` (the active view's column_styles).
 *  Conditional rows ride the Reveal disclosure — the DateTimeEditor Day-row pattern. */
export function NumberEditor({
  config,
  look,
  onSetConfig,
  onSetStyle
}: {
  config: NumberConfig
  look: NumberLook
  onSetConfig: (patch: Partial<NumberConfig>) => void
  onSetStyle: (look: NumberLook) => void
}): React.JSX.Element {
  const family: NumberFamily = config.number_family ?? 'number'
  const isPercent = family === 'percent'
  const fraction = config.number_fraction ?? false

  return (
    <div className={configEditor}>
      <span className={optionsLabel}>Format</span>

      <div className={configRow}>
        <span className={configLabel}>Format</span>
        <PickerControl ariaLabel="Number format" value={family} options={FAMILY_OPTIONS} onPick={(v) => onSetConfig({ number_family: v })} />
      </div>

      <Reveal open={family === 'currency'} fill>
        <div className={configRow}>
          <span className={configLabel}>Currency</span>
          <PickerControl
            ariaLabel="Currency"
            value={config.number_currency ?? 'USD'}
            options={CURRENCY_OPTIONS}
            onPick={(v) => onSetConfig({ number_currency: v })}
          />
        </div>
      </Reveal>

      <Reveal open={!isPercent} fill>
        <div className={configRow}>
          <span className={configLabel}>Separators</span>
          <span className={switchScale}>
            <Switch checked={config.number_separators ?? true} onChange={(next) => onSetConfig({ number_separators: next })} ariaLabel="Separators" />
          </span>
        </div>
      </Reveal>

      <div className={configRow}>
        <span className={configLabel}>Decimals</span>
        <PickerControl
          ariaLabel="Decimal places"
          value={decimalsToPicker(config.number_decimals)}
          options={DECIMAL_OPTIONS}
          onPick={(v) => onSetConfig({ number_decimals: pickerToDecimals(v) })}
        />
      </div>

      <Reveal open={!isPercent} fill>
        <div className={configRow}>
          <span className={configLabel}>Fraction</span>
          <span className={switchScale}>
            <Switch checked={fraction} onChange={(next) => onSetConfig({ number_fraction: next })} ariaLabel="Fraction" />
          </span>
        </div>
      </Reveal>

      <Reveal open={!isPercent && fraction} fill>
        <div className={configRow}>
          <span className={configLabel}>Value</span>
          <input
            className={s.valueInput}
            type="number"
            aria-label="Fraction value"
            defaultValue={config.number_denominator ?? ''}
            onBlur={(e) => {
              const n = Number.parseFloat(e.target.value)
              onSetConfig({ number_denominator: Number.isNaN(n) ? undefined : n })
            }}
          />
        </div>
      </Reveal>

      <Reveal open={isPercent || fraction} fill>
        <div className={configRow}>
          <span className={configLabel}>Style</span>
          <PickerControl ariaLabel="Number style" value={look} options={STYLE_OPTIONS} onPick={onSetStyle} />
        </div>
      </Reveal>
    </div>
  )
}
```

- [ ] **Step 5: Run to verify the component test passes**

Run: `cd Pommora && npx vitest run src/renderer/src/Components/Detail/NumberEditor.test.tsx`
Expected: PASS. (If `text.control.emphasized` isn't the exact typography accessor `configLabel` uses, mirror `settingsPane.css.ts:353` exactly.)

- [ ] **Step 6: Wire PropertiesPane**

In `src/renderer/src/Components/Detail/PropertiesPane.tsx`, add the import near the other editor imports (with `CheckboxEditor`):

```typescript
import { NumberEditor } from './NumberEditor'
import type { NumberConfig } from '@shared/properties'
```

Add the save callback after `saveCheckboxColor` (~line 256):

```typescript
  // A number property's format is def-level (property-wide) — its own IPC, not the view's column_styles.
  const saveNumberFormat = async (id: string, patch: Partial<NumberConfig>): Promise<void> => {
    await commit(await window.nexus.property.setNumberFormat(id, patch))
  }
```

Add the branch before the final `else` (the blank stub) at ~line 399 — insert after the `checkbox` branch's closing `/>`:

```typescript
        ) : def.type === 'number' ? (
          <NumberEditor
            config={{
              number_family: def.number_family,
              number_currency: def.number_currency,
              number_separators: def.number_separators,
              number_decimals: def.number_decimals,
              number_fraction: def.number_fraction,
              number_denominator: def.number_denominator
            }}
            look={styleFor(def.id, schema, activeView).look === 'bar' ? 'bar' : 'number'}
            onSetConfig={(patch) => void saveNumberFormat(def.id, patch)}
            onSetStyle={(look) => saveColumnStyle(def.id, { look })}
          />
```

- [ ] **Step 7: Full gate + commit**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck && npx vitest run && env -u ELECTRON_RUN_AS_NODE npm run build`
Expected: typecheck exit 0, all vitest green, build succeeds.

```bash
git add "Pommora/src/renderer/src/Components/Detail/NumberEditor.tsx" "Pommora/src/renderer/src/Components/Detail/numberEditor.css.ts" "Pommora/src/renderer/src/Components/Detail/NumberEditor.test.tsx" "Pommora/src/renderer/src/Components/Detail/PropertiesPane.tsx"
git commit -m "feat(number): NumberEditor pane + PropertiesPane wiring"
```

---

### Task 8: Reconcile the docs

**Files:**
- Modify: `.claude/Features/Properties.md` (§"Where Properties Live"; Pending "Per-Type Editor Panes" + "Display Formats"; add a `#### II. Number` section)
- Modify: `.claude/Features/Views.md` (the `column_styles` description — number format is def-level, not per-view)
- Modify: `.claude/History.md` (one entry) + `.claude/Handoff.md` (mark shipped)

**No test — documentation.** Follow the docs' existing voice; describe durable decisions, name tokens (never restate `#hex`/px/line values).

- [ ] **Step 1: Add the Number property section to Properties.md**

After the `#### II. Checkbox` section, add a `#### II. Number` section describing: a bare number on disk; **property-wide** (def-level) format config — family (Number / Percent / Currency), currency code, thousands Separators (Number & Currency), Decimals (Hidden or 1–10), and a Fraction toggle that renders "N out of Value" (Number & Currency only); Percent stores the literal and appends `%`; a **per-view** Style/look (Number or Bar) where Bar draws an accent progress bar over a label-control track, filling `value ÷ Value` (fraction) or `value ÷ 100` (percent); the editor exposes the format as a Format section with conditional (Reveal-animated) Currency/Separators/Fraction/Value/Style rows.

- [ ] **Step 2: Fix the stale per-view claim**

In Properties.md §"Where Properties Live", the line stating number formats persist per-VIEW in `column_styles` is now wrong for the format itself — restate it: date/time formats + the per-type *look* (incl. Number's Number/Bar) persist per-VIEW; **Number's format config is def-level** (property-wide), like the checkbox colour and link config. In the Pending list, strike the "Number value-type pane / number-format picker" gap and the "property-editor Format surface for Number" gap — both shipped. In Views.md, amend the `column_styles` description so it no longer claims number *format* choices live there (the look does; the format is def-level).

- [ ] **Step 3: History + Handoff**

Add a `History.md` entry: "Number Property Editor — def-level format (family/currency/separators/decimals/fraction) + per-view Number/Bar look + ProgressBar component; removed the per-view number_format enum." Update `Handoff.md` (Number editor shipped; the last per-type pane — only relation/context pickers remain per Properties.md Pending). Note the build-time eyeball items (Decimals "Hidden" semantics, fraction wording, bar clamp, bar strokeless look) in the Handoff Fix Log / Next Session.

- [ ] **Step 4: Commit**

```bash
git add "The Studio/Projects/Project Pommora/.claude/Features/Properties.md" "The Studio/Projects/Project Pommora/.claude/Features/Views.md" "The Studio/Projects/Project Pommora/.claude/History.md" "The Studio/Projects/Project Pommora/.claude/Handoff.md"
git commit -m "docs(number): reconcile Properties/Views + log the Number editor shipped"
```

**Staging note:** stage explicit files only (a parallel session may hold uncommitted changes — never `git add -A` / `git add .`). Adjust the doc paths to whatever the working directory makes correct.

---

## Self-Review

**Spec coverage** (against the decision log):
- Def-level fields + IPC → Tasks 1, 6. ✓
- `number`/`bar` looks + `STYLE_VALUES.look` free coverage → Task 2. ✓
- Remove per-view `number_format`, repurpose `styleMenuItems('number')` (F2) → Task 5. ✓
- `formatNumber` rewrite (literal percent, Hidden=integer, fraction "N out of Value"), single caller Cell.tsx → Task 4. ✓
- ProgressBar component (accent/label-control/no stroke, clamp) → Task 3; cell render → Task 4. ✓
- NumberEditor pane (conditional Reveal chain, def writes IPC, look writes saveColumnStyle) → Task 7. ✓
- Test migration (formatValue/columnStyles/columnMenu/cellMenu/Cell) → Tasks 4, 5. ✓
- Docs (Properties/Views + F1 `build.ts` name-collision honoured via the field names) → Tasks 1, 8. ✓
- F1 `build.ts:187 configOf` — the new fields deliberately do NOT join it (cosmetic def config stays off the index, matching checkbox/link); the field names avoid the `number_format` collision. No task edits `build.ts`. ✓
- E-2 value preservation — free: def-level fields aren't cleared by hiding a Reveal row (no write fires). No task needed. ✓

**Green-at-each-step:** Task order dodges the two lockstep traps — `'bar'` enters `COLUMN_LOOKS` (Task 2) before the Cell compares `look === 'bar'` (Task 4); `formatNumber`'s signature change (Task 4) updates its sole caller in the same task; `number_format` removal (Task 5) lands only after nothing reads it.

**Build-time eyeball items** (intentionally unresolved — flagged for Nathan, not gaps): Decimals "Hidden" exact semantics, fraction wording ("N out of M" vs "N/M" — currently "N out of M"), bar clamp behaviour at the edges, the strokeless bar look, bar height/centering.

**Type consistency:** `NumberConfig`/`NumberFamily`/`CURRENCY_CODES` (Task 1) are consumed verbatim in Tasks 4, 7. `NumberLook = 'number'|'bar'` (Task 7) matches the `COLUMN_LOOKS` additions (Task 2). `numberDivisor`/`formatNumber` signatures (Task 4) match their Cell + test call sites.
