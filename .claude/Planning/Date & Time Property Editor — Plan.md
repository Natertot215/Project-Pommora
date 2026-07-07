# Date & Time Property Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill the blank `datetime` branch of the PropertiesPane property editor with a **Format** section — a Date picker, a conditional Day (weekday) picker, and a Time picker — that writes the property's per-view display format into the active view's `column_styles`.

**Architecture:** The per-view date/time format already ships end-to-end (data in `SavedView.column_styles`, rendered by `Cell.tsx` via `formatDate`, set via the table column-header Style menu). This adds a second, discoverable surface (the property editor) plus two net-new format pieces: a decoupled **weekday** dimension (pulled out of `full`) and a **Relative** format. Writes reuse the one view writer, `saveViewAdopting`.

**Tech Stack:** Electron 42 · React 19 · TypeScript 6 · Zustand · Vitest · vanilla-extract CSS. Renderer↔main via typed IPC; `src/shared` is the cross-process contract.

## Global Constraints

- **Spec source of truth:** `.claude/Planning/Date & Time Property Editor — Decision Log.md` (review-certified). Every decision tag (A-*, B-*, C-*, D-*, E-*) is referenced below.
- **The gate is `npm run typecheck` (two tsc passes) + `npx vitest run` + `npm run build`.** The Vite build strips types without checking, so typecheck is the ONLY type-safety gate. Run all three before each commit. Launch with `env -u ELECTRON_RUN_AS_NODE` prefix for build.
- **Never run Biome** — a PostToolUse hook formats on write. Write correct code; don't hand-align.
- **Colors** authored as hex from `design-system/tokens`; never `rgb()`. New files PascalCase.
- **Adding `'relative'` to the `DateFormat` union breaks `formatDate` + `condensedDate` typecheck** (both are `default`-less exhaustive switches — TS2454 / TS2366). Sequence: the weekday field (Task 1) and the weekday `formatDate` param (Task 2) are additive/green; the `'relative'` union member lands ONLY in Task 3, together with its switch arms, so the gate is never left red.
- **`formatDate` stays pure/testable:** relative-to-now injects `now: Date = new Date()` as its last param so tests pin a fixed clock. `new Date()` in renderer code is fine (the Date.now/Math.random ban is workflow-script-only).
- **Enum values:** `WEEKDAY_FORMATS = ['long', 'short', 'none']` (Intl-aligned; UI labels Full/Short/Hidden). `DATE_FORMATS` gains `'relative'`.
- **Labels are Title-Case, capitalized** (B-7): "Month/Day/Year", "Full Date", "12 Hours", "3 Days Ago".
- **Relative thresholds** (C-3, Nathan-tunable): "within a week" = |Δdays| ≤ 7. No absolute fallback at the far end (stays `N Years Ago`). Keep these as named constants so Nathan can eyeball them.

---

## File Structure

- `src/shared/columnStyles.ts` *(modify)* — `WEEKDAY_FORMATS` + `WeekdayFormat`; `'relative'` in `DATE_FORMATS`; `weekday` on `columnStyle` zod; `weekday: 'none'` in `defaultStyleFor('datetime'/'last_edited_time')`.
- `src/renderer/src/Detail/Views/PropertyEditing/formatValue.ts` *(modify)* — `formatDate` gains `weekday` + `now` params, `full` reshaped weekday-free, weekday-prepend, `relative` arm (`formatRelative` helper); `condensedDate` gains a `relative` early-return.
- `src/renderer/src/Detail/Views/PropertyEditing/formatValue.test.ts` *(modify)* — reshaped `full`, new weekday + relative cases.
- `src/renderer/src/Detail/Views/Table/Cell.tsx` *(modify)* — forward `style.weekday` into `formatDate`.
- `src/renderer/src/Detail/Views/Table/TableView.tsx` *(modify)* — coerce `relative → short` at the CalendarPicker boundary (line ~611).
- `src/shared/columnMenu.ts` *(modify)* — `styleMenuItems('datetime')` gains the Relative date row + 3 weekday radios; `STYLE_VALUES.weekday`.
- `src/shared/columnMenu.test.ts` *(modify/create if absent)* — weekday radios present; `parseStyleAction('style:weekday:long')` resolves.
- `src/renderer/src/Components/Detail/DateTimeEditor.tsx` *(create)* — the editor UI (3 picker rows, Day conditional via `Reveal`).
- `src/renderer/src/Components/Detail/dateTimeEditor.css.ts` *(create)* — the section + row styles.
- `src/renderer/src/Components/Detail/PropertiesPane.tsx` *(modify)* — datetime branch renders `DateTimeEditor`; add `saveColumnStyle`; accept `source` + `view`.
- `src/renderer/src/Components/Detail/SettingsPane.tsx` *(modify)* — pass `source={node}` + `view={pickView(node, activeViewId, schema)}` to `PropertiesPane`.
- Docs *(modify)* — `Features/Properties.md`, `Features/Views.md`, `History.md`.

---

### Task 1: The `weekday` field + `relative` value slot (shared data layer)

**Files:**
- Modify: `src/shared/columnStyles.ts`
- Test: `src/shared/columnStyles.test.ts` (create if absent)

**Interfaces:**
- Produces: `WEEKDAY_FORMATS = ['long','short','none'] as const`; `type WeekdayFormat`; `columnStyle.weekday?: WeekdayFormat`; `DATE_FORMATS` includes `'relative'`; `defaultStyleFor('datetime') = { date_format:'full', time_format:'none', weekday:'none' }`.

- [ ] **Step 1: Write the failing test**

```ts
// src/shared/columnStyles.test.ts
import { describe, it, expect } from 'vitest'
import { columnStyle, defaultStyleFor, WEEKDAY_FORMATS, DATE_FORMATS } from './columnStyles'

describe('columnStyle weekday + relative', () => {
  it('parses a weekday field', () => {
    expect(columnStyle.parse({ weekday: 'long' })).toEqual({ weekday: 'long' })
  })
  it('drops an unknown weekday to undefined (lenient catch)', () => {
    expect(columnStyle.parse({ weekday: 'bogus' }).weekday).toBeUndefined()
  })
  it('datetime default carries weekday none', () => {
    expect(defaultStyleFor('datetime')).toEqual({ date_format: 'full', time_format: 'none', weekday: 'none' })
  })
  it('relative is a date format; long/short/none are weekday formats', () => {
    expect(DATE_FORMATS).toContain('relative')
    expect(WEEKDAY_FORMATS).toEqual(['long', 'short', 'none'])
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/shared/columnStyles.test.ts`
Expected: FAIL — `WEEKDAY_FORMATS` undefined; `DATE_FORMATS` lacks `'relative'`; default lacks `weekday`.

- [ ] **Step 3: Implement**

In `src/shared/columnStyles.ts`, extend the enums, the codec, and the default. Add `'relative'` to `DATE_FORMATS`; add `WEEKDAY_FORMATS`; add `weekday` to `columnStyle`; add `weekday: 'none'` to the datetime branch of `defaultStyleFor`:

```ts
export const DATE_FORMATS = ['short', 'full', 'dayMonthYear', 'monthDayYear', 'relative'] as const
export type DateFormat = (typeof DATE_FORMATS)[number]

export const TIME_FORMATS = ['none', 'twelveHour', 'twentyFourHour'] as const
export type TimeFormat = (typeof TIME_FORMATS)[number]

export const WEEKDAY_FORMATS = ['long', 'short', 'none'] as const
export type WeekdayFormat = (typeof WEEKDAY_FORMATS)[number]
```

```ts
export const columnStyle = z.looseObject({
  look: z.enum(COLUMN_LOOKS).optional().catch(undefined),
  date_format: z.enum(DATE_FORMATS).optional().catch(undefined),
  time_format: z.enum(TIME_FORMATS).optional().catch(undefined),
  weekday: z.enum(WEEKDAY_FORMATS).optional().catch(undefined),
  number_format: z.enum(NUMBER_FORMATS).optional().catch(undefined)
})
```

```ts
// inside defaultStyleFor:
    case 'datetime':
    case 'last_edited_time':
      return { date_format: 'full', time_format: 'none', weekday: 'none' }
```

- [ ] **Step 4: Run test + typecheck**

Run: `npx vitest run src/shared/columnStyles.test.ts && env -u ELECTRON_RUN_AS_NODE npm run typecheck`
Expected: test PASS. **Typecheck will FAIL** in `formatValue.ts` (TS2454/TS2366 — `'relative'` unhandled). This is expected and resolved in Task 3; Tasks 2 and 3 are done back-to-back. Do NOT commit a red typecheck — **fold Tasks 1–3 into one commit** (they share the gate). Proceed to Task 2 without committing.

---

### Task 2: `formatDate` weekday decomposition + `full` reshape

**Files:**
- Modify: `src/renderer/src/Detail/Views/PropertyEditing/formatValue.ts`
- Modify: `src/renderer/src/Detail/Views/Table/Cell.tsx`
- Test: `src/renderer/src/Detail/Views/PropertyEditing/formatValue.test.ts`

**Interfaces:**
- Consumes: `WeekdayFormat` (Task 1).
- Produces: `formatDate(iso, dateFormat, timeFormat, weekday?: WeekdayFormat, now?: Date): string` — `full` = `Month Ordinal, Year` (no weekday); weekday prepends for short/full only.

- [ ] **Step 1: Write the failing tests** (append to `formatValue.test.ts`; UPDATE the existing `full` assertion)

```ts
import { formatDate } from './formatValue'

describe('formatDate weekday + reshaped full', () => {
  const iso = '2026-07-06' // a Monday
  it('full is weekday-free: Month Ordinal, Year', () => {
    expect(formatDate(iso, 'full', 'none')).toBe('July 6th, 2026')
  })
  it('short is Month Ordinal', () => {
    expect(formatDate(iso, 'short', 'none')).toBe('July 6th')
  })
  it('long weekday prepends on full', () => {
    expect(formatDate(iso, 'full', 'none', 'long')).toBe('Monday, July 6th, 2026')
  })
  it('short weekday prepends on short', () => {
    expect(formatDate(iso, 'short', 'none', 'short')).toBe('Mon, July 6th')
  })
  it('weekday is ignored on numeric formats', () => {
    expect(formatDate(iso, 'monthDayYear', 'none', 'long')).toBe('07/06/2026')
  })
  it('weekday none adds nothing', () => {
    expect(formatDate(iso, 'full', 'none', 'none')).toBe('July 6th, 2026')
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/renderer/src/Detail/Views/PropertyEditing/formatValue.test.ts`
Expected: FAIL — existing `full` still emits the weekday form; `formatDate` takes no 4th arg.

- [ ] **Step 3: Implement** — reshape `full`, add the `weekday` + `now` params, prepend the weekday for short/full. Replace the `formatDate` body:

```ts
export function formatDate(
  iso: string,
  dateFormat: DateFormat,
  timeFormat: TimeFormat,
  weekday: WeekdayFormat = 'none',
  now: Date = new Date()
): string {
  const hasTime = iso.includes('T')
  const date = new Date(hasTime ? iso : `${iso}T00:00:00`)
  if (Number.isNaN(date.getTime())) return iso
  if (dateFormat === 'relative') return formatRelative(date, hasTime, timeFormat, now)

  const month = date.toLocaleDateString('en-US', { month: 'long' })
  const day = ordinal(date.getDate())
  let out: string
  switch (dateFormat) {
    case 'short':
      out = `${month} ${day}`
      break
    case 'full':
      out = `${month} ${day}, ${date.getFullYear()}`
      break
    case 'dayMonthYear':
      out = `${pad(date.getDate())}/${pad(date.getMonth() + 1)}/${date.getFullYear()}`
      break
    case 'monthDayYear':
      out = `${pad(date.getMonth() + 1)}/${pad(date.getDate())}/${date.getFullYear()}`
      break
  }

  if ((dateFormat === 'short' || dateFormat === 'full') && weekday !== 'none') {
    const wd = date.toLocaleDateString('en-US', { weekday: weekday === 'long' ? 'long' : 'short' })
    out = `${wd}, ${out}`
  }
  if (hasTime && timeFormat !== 'none') {
    out += ` ${clockOf(date, timeFormat)}`
  }
  return out
}
```

Add the shared clock helper (extracted from the old inline time block) above `formatDate`:

```ts
function clockOf(date: Date, timeFormat: TimeFormat): string {
  return timeFormat === 'twelveHour'
    ? date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
    : date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false })
}
```

Add a `WeekdayFormat` import and a **temporary** `formatRelative` stub so this task compiles standalone (real logic lands in Task 3):

```ts
import type { DateFormat, NumberFormat, TimeFormat, WeekdayFormat } from '@shared/columnStyles'

function formatRelative(date: Date, hasTime: boolean, timeFormat: TimeFormat, now: Date): string {
  return date.toLocaleDateString('en-US') // TASK 3 replaces this
}
```

In `Cell.tsx` (~line 137-142), forward the weekday:

```ts
case 'datetime':
  return (
    <OverflowScroll className="cell-text-scroll cell-muted">
      {formatDate(v.value, style.date_format ?? 'full', style.time_format ?? 'none', style.weekday ?? 'none')}
    </OverflowScroll>
  )
```

- [ ] **Step 4: Run the formatValue tests + typecheck**

Run: `npx vitest run src/renderer/src/Detail/Views/PropertyEditing/formatValue.test.ts`
Expected: PASS. (Full typecheck still red on `condensedDate` — resolved next task. Continue.)

---

### Task 3: The `relative` format + CalendarPicker coercion (closes the gate)

**Files:**
- Modify: `src/renderer/src/Detail/Views/PropertyEditing/formatValue.ts`
- Modify: `src/renderer/src/Detail/Views/Table/TableView.tsx`
- Test: `src/renderer/src/Detail/Views/PropertyEditing/formatValue.test.ts`

**Interfaces:**
- Produces: real `formatRelative`; `condensedDate` handles `'relative'`; TableView coerces a `relative` column to `short` before the CalendarPicker.

- [ ] **Step 1: Write the failing tests** (fixed `now`; day 2026-07-06 as "today")

```ts
describe('formatDate relative', () => {
  const now = new Date('2026-07-06T12:00:00')
  const rel = (iso: string, time: 'none' | 'twelveHour' = 'none') =>
    formatDate(iso, 'relative', time, 'none', now)
  it('today / yesterday / tomorrow', () => {
    expect(rel('2026-07-06')).toBe('Today')
    expect(rel('2026-07-05')).toBe('Yesterday')
    expect(rel('2026-07-07')).toBe('Tomorrow')
  })
  it('within a week counts days both directions', () => {
    expect(rel('2026-07-03')).toBe('3 Days Ago')
    expect(rel('2026-07-09')).toBe('In 3 Days')
  })
  it('past a week rolls to weeks / months / years', () => {
    expect(rel('2026-06-20')).toBe('2 Weeks Ago')
    expect(rel('2026-04-06')).toBe('3 Months Ago')
    expect(rel('2024-07-06')).toBe('2 Years Ago')
  })
  it('time-shown appends the clock within a week, drops it past a week', () => {
    expect(rel('2026-07-06T15:30:00', 'twelveHour')).toBe('Today at 3:30 PM')
    expect(rel('2026-07-05T15:30:00', 'twelveHour')).toBe('Yesterday at 3:30 PM')
    expect(rel('2026-06-20T15:30:00', 'twelveHour')).toBe('2 Weeks Ago')
  })
  it('condensedDate treats relative as the worded short form (never shown relative in the picker)', () => {
    expect(condensedDate('2026-07-06', 'relative', true)).toBe('July 6th')
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/renderer/src/Detail/Views/PropertyEditing/formatValue.test.ts`
Expected: FAIL — stub `formatRelative` returns a locale date; `condensedDate` has no relative arm (TS + runtime).

- [ ] **Step 3: Implement** — replace the stub with the real relative logic + add the `condensedDate` early-return:

```ts
// ── Relative thresholds (Nathan-tunable) ──
const WEEK_DAYS = 7 // |Δdays| ≤ this shows named/day-count form (with clock when time-shown)

function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}

/** Capitalized relative wording. Within a week: named day / "N Days Ago" / "In N Days" (+ "at <clock>"
 *  when time is shown). Past a week: weeks → months → years, clock dropped. */
function formatRelative(date: Date, hasTime: boolean, timeFormat: TimeFormat, now: Date): string {
  const DAY = 86_400_000
  const diffDays = Math.round((startOfDay(date).getTime() - startOfDay(now).getTime()) / DAY)
  const ago = diffDays < 0
  const n = Math.abs(diffDays)

  if (n <= WEEK_DAYS) {
    const dayWord = n === 0 ? 'Today' : n === 1 ? (ago ? 'Yesterday' : 'Tomorrow') : ago ? `${n} Days Ago` : `In ${n} Days`
    return hasTime && timeFormat !== 'none' ? `${dayWord} at ${clockOf(date, timeFormat)}` : dayWord
  }
  const weeks = Math.round(n / 7)
  const months = Math.round(n / 30)
  const years = Math.round(n / 365)
  const [unit, count] = n < 30 ? ['Week', weeks] : n < 365 ? ['Month', months] : ['Year', years]
  const plural = count === 1 ? unit : `${unit}s`
  return ago ? `${count} ${plural} Ago` : `In ${count} ${plural}`
}
```

Add the `condensedDate` relative early-return (right after the NaN guard, before the switch):

```ts
export function condensedDate(iso: string, dateFormat: DateFormat, withYear: boolean): string {
  const date = new Date(iso.includes('T') ? iso : `${iso}T00:00:00`)
  if (Number.isNaN(date.getTime())) return iso
  if (dateFormat === 'relative') return `${date.toLocaleDateString('en-US', { month: 'long' })} ${ordinal(date.getDate())}`
  switch (dateFormat) {
    // ...unchanged short/full/dayMonthYear/monthDayYear
  }
}
```

In `TableView.tsx` (~line 611), coerce a relative column to a concrete date format before the entry picker so you never enter a date rendered "3 Days Ago":

```ts
const rawFmt = colStyle(col.id).date_format ?? 'full'
const dateFmt = rawFmt === 'relative' ? 'short' : rawFmt
```

- [ ] **Step 4: Run tests + full typecheck + build**

Run: `npx vitest run src/renderer/src/Detail/Views/PropertyEditing/formatValue.test.ts && env -u ELECTRON_RUN_AS_NODE npm run typecheck && npx vitest run`
Expected: all PASS, typecheck GREEN (both switches exhaustive again).

- [ ] **Step 5: Commit (Tasks 1–3 together — one green gate)**

```bash
env -u ELECTRON_RUN_AS_NODE npm run build
git add src/shared/columnStyles.ts src/shared/columnStyles.test.ts \
  src/renderer/src/Detail/Views/PropertyEditing/formatValue.ts \
  src/renderer/src/Detail/Views/PropertyEditing/formatValue.test.ts \
  src/renderer/src/Detail/Views/Table/Cell.tsx \
  src/renderer/src/Detail/Views/Table/TableView.tsx
git commit -m "feat(columns): decouple weekday, reshape full, add relative date format

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Native-menu parity — weekday radios + STYLE_VALUES allowlist

**Files:**
- Modify: `src/shared/columnMenu.ts`
- Test: `src/shared/columnMenu.test.ts` (create if absent)

**Interfaces:**
- Consumes: `WEEKDAY_FORMATS`, `DATE_FORMATS` (with `relative`).
- Produces: `styleMenuItems('datetime')` includes a Relative date radio + 3 weekday radios; `parseStyleAction('style:weekday:long')` resolves.

- [ ] **Step 1: Write the failing test**

```ts
// src/shared/columnMenu.test.ts
import { describe, it, expect } from 'vitest'
import { styleMenuItems, parseStyleAction } from './columnMenu'
import { defaultStyleFor } from './columnStyles'

describe('datetime style menu — weekday + relative', () => {
  const items = styleMenuItems({ type: 'datetime', current: defaultStyleFor('datetime') })
  it('offers the Relative date radio', () => {
    expect(items.find((i) => i.key === 'date_format' && i.value === 'relative')?.label).toBe('Relative')
  })
  it('offers Full/Short/Hidden weekday radios', () => {
    const wd = items.filter((i) => i.key === 'weekday').map((i) => [i.label, i.value])
    expect(wd).toEqual([['Full', 'long'], ['Short', 'short'], ['Hidden', 'none']])
  })
  it('parseStyleAction accepts a weekday action', () => {
    expect(parseStyleAction('style:weekday:long')).toEqual({ key: 'weekday', value: 'long' })
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/shared/columnMenu.test.ts`
Expected: FAIL — no Relative/weekday rows; `parseStyleAction('style:weekday:long')` returns `null`.

- [ ] **Step 3: Implement** — in `columnMenu.ts`, extend the datetime branch of `styleMenuItems` and the `STYLE_VALUES` allowlist. Import `WEEKDAY_FORMATS`:

```ts
import { COLUMN_LOOKS, DATE_FORMATS, NUMBER_FORMATS, TIME_FORMATS, WEEKDAY_FORMATS, type ColumnStyle } from './columnStyles'
```

```ts
    case 'datetime':
    case 'last_edited_time': {
      const date = row('date_format', current.date_format)
      const weekday = row('weekday', current.weekday)
      const time = row('time_format', current.time_format)
      return [
        date('Month/Day/Year', 'monthDayYear'),
        date('Day/Month/Year', 'dayMonthYear'),
        date('Short Date', 'short'),
        date('Full Date', 'full'),
        date('Relative', 'relative'),
        weekday('Full', 'long', true),
        weekday('Short', 'short'),
        weekday('Hidden', 'none'),
        time('12 Hours', 'twelveHour', true),
        time('24 Hours', 'twentyFourHour'),
        time('Hidden', 'none')
      ]
    }
```

```ts
const STYLE_VALUES: Record<string, readonly string[]> = {
  look: COLUMN_LOOKS,
  date_format: DATE_FORMATS,
  time_format: TIME_FORMATS,
  weekday: WEEKDAY_FORMATS,
  number_format: NUMBER_FORMATS
}
```

- [ ] **Step 4: Run tests + typecheck**

Run: `npx vitest run src/shared/columnMenu.test.ts && env -u ELECTRON_RUN_AS_NODE npm run typecheck`
Expected: PASS + GREEN.

- [ ] **Step 5: Commit**

```bash
git add src/shared/columnMenu.ts src/shared/columnMenu.test.ts
git commit -m "feat(columnMenu): datetime Style menu gains Relative + weekday radios

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Thread the view into PropertiesPane + the per-view write path

**Files:**
- Modify: `src/renderer/src/Components/Detail/PropertiesPane.tsx`
- Modify: `src/renderer/src/Components/Detail/SettingsPane.tsx`

**Interfaces:**
- Consumes: `pickView` (`../../Detail/Views/Table/TableView`), `saveViewAdopting` (`../../Detail/Views/viewMint`), `styleFor` (`../../Detail/Views/Table/columnStyles`), `ColumnStyle`.
- Produces: `PropertiesPane` accepts `source: CollectionNode | SetNode` + `view: SavedView`; exposes `saveColumnStyle(propId, patch: Partial<ColumnStyle>)` used by Task 6.

**Why source ≠ collectionPath (decision A-3):** For a depth-1 Set, `node` (owns `views[]` + `activeViews[node.id]`) diverges from `schemaCollection` (owns `schema` + `collectionPath`). The view write MUST target `node`; the schema writes keep using `collectionPath`. Thread both.

- [ ] **Step 1: Write the failing test** (component-level, jsdom — asserts the write targets the source node's view)

```tsx
// src/renderer/src/Components/Detail/propertiesPane.datetime.test.tsx
// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach } from 'vitest'
// Mint a minimal source node + a datetime property in schema, render PropertiesPane
// opened on the datetime editor, click Date → "Short Date", assert window.nexus.views.save
// was called with source.path and column_styles[propId].date_format === 'short'.
// (Follow the existing propertiesPane.test.tsx harness for store + nexus stubs.)
```

Model the harness on the existing `propertiesPane.test.tsx` (store seeding + `window.nexus` stubs). The assertion:

```tsx
expect(saveSpy).toHaveBeenCalledWith('Col', 'collection', expect.objectContaining({
  column_styles: expect.objectContaining({ [dateProp.id]: expect.objectContaining({ date_format: 'short' }) })
}))
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/renderer/src/Components/Detail/propertiesPane.datetime.test.tsx`
Expected: FAIL — datetime branch is a blank stub; `PropertiesPane` takes no `source`/`view`.

- [ ] **Step 3: Implement the plumbing** (the editor UI itself is Task 6; here, wire props + the write helper).

In `PropertiesPane.tsx`, extend the props and add the write helper (place near `saveLinkConfig`):

```ts
// signature — add to the existing props object:
  source,
  view,
// ...
}: {
  collectionPath: string
  schema: PropertyDefinition[]
  onBack: () => void
  source: CollectionNode | SetNode
  view: SavedView
}) {
```

```ts
import { saveViewAdopting } from '../../Detail/Views/viewMint'
import { styleFor } from '../../Detail/Views/Table/columnStyles'
import type { ColumnStyle } from '@shared/columnStyles'
```

```ts
// Per-VIEW display style for a property (date/time/number format, look) — writes the ACTIVE view's
// column_styles, NOT the nexus schema. Reuses the one view writer.
const saveColumnStyle = (propId: string, patch: Partial<ColumnStyle>): void => {
  const next = { ...view.column_styles?.[propId], ...patch }
  void saveViewAdopting(source, { ...view, column_styles: { ...view.column_styles, [propId]: next } }, load)
}
const resolvedStyle = (propId: string): ColumnStyle => styleFor(propId, schema, view)
```

In `SettingsPane.tsx`, pass the source node + resolved active view (line ~151):

```tsx
<PropertiesPane
  collectionPath={schemaCollection.path}
  schema={schema}
  onBack={back}
  source={node}
  view={pickView(node, activeViewId, schema)}
/>
```

`pickView` is already imported in SettingsPane (`import { pickView } from '../../Detail/Views/Table/TableView'`, used at the Layout leaf). `activeViewId` already exists (`const activeViewId = useSession((st) => st.activeViews[node.id])`).

- [ ] **Step 4: Run test + typecheck + build**

Run: `npx vitest run src/renderer/src/Components/Detail/propertiesPane.datetime.test.tsx && env -u ELECTRON_RUN_AS_NODE npm run typecheck`
Expected: the write-path test PASSes once Task 6 renders the editor; if you split, assert `saveColumnStyle` directly in a unit test here and defer the click-through assertion to Task 6. Typecheck GREEN.

- [ ] **Step 5: Commit** (fold with Task 6 if the click-through test needs the UI — otherwise commit the plumbing)

```bash
git add src/renderer/src/Components/Detail/PropertiesPane.tsx src/renderer/src/Components/Detail/SettingsPane.tsx
git commit -m "feat(properties): thread the active view + a per-view column-style writer into the editor

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: The DateTimeEditor UI (Date / Day / Time picker rows)

**Files:**
- Create: `src/renderer/src/Components/Detail/DateTimeEditor.tsx`
- Create: `src/renderer/src/Components/Detail/dateTimeEditor.css.ts`
- Modify: `src/renderer/src/Components/Detail/PropertiesPane.tsx` (render it in the datetime branch)
- Test: `src/renderer/src/Components/Detail/dateTimeEditor.test.tsx`

**Interfaces:**
- Consumes: `saveColumnStyle`, `resolvedStyle` (Task 5); `PickerMenu` + `PickerOption` (`../../design-system/components/PickerMenu`); `Reveal` (`../../design-system/components/Reveal`); `Icon`.
- Produces: `DateTimeEditor({ style: ColumnStyle, onChange: (patch: Partial<ColumnStyle>) => void })`.

- [ ] **Step 1: Write the failing test**

```tsx
// @vitest-environment jsdom
import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react' // or the project's act-based harness
import { DateTimeEditor } from './DateTimeEditor'

describe('DateTimeEditor', () => {
  it('shows the Day row only for short/full', () => {
    const { rerender, queryByText } = render(<DateTimeEditor style={{ date_format: 'monthDayYear' }} onChange={() => {}} />)
    expect(queryByText('Day')).toBeNull()
    rerender(<DateTimeEditor style={{ date_format: 'full' }} onChange={() => {}} />)
    expect(queryByText('Day')).not.toBeNull()
  })
  it('emits a date_format patch on pick', () => {
    const onChange = vi.fn()
    render(<DateTimeEditor style={{ date_format: 'full' }} onChange={onChange} />)
    fireEvent.click(screen.getByLabelText('Date format'))
    fireEvent.click(screen.getByText('Short Date'))
    expect(onChange).toHaveBeenCalledWith({ date_format: 'short' })
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/renderer/src/Components/Detail/dateTimeEditor.test.tsx`
Expected: FAIL — module doesn't exist.

- [ ] **Step 3: Implement** the component + a small internal `PickerRow`:

```tsx
// DateTimeEditor.tsx
import { useRef, useState } from 'react'
import type { ColumnStyle, DateFormat, TimeFormat, WeekdayFormat } from '@shared/columnStyles'
import { Icon, type IconName } from '@renderer/design-system/symbols'
import { PickerMenu, PickerOption } from '../../design-system/components/PickerMenu'
import { Reveal } from '../../design-system/components/Reveal'
import * as s from './dateTimeEditor.css'

const DATE_OPTIONS: { value: DateFormat; label: string }[] = [
  { value: 'monthDayYear', label: 'Month/Day/Year' },
  { value: 'dayMonthYear', label: 'Day/Month/Year' },
  { value: 'short', label: 'Short Date' },
  { value: 'full', label: 'Full Date' },
  { value: 'relative', label: 'Relative' }
]
const WEEKDAY_OPTIONS: { value: WeekdayFormat; label: string }[] = [
  { value: 'long', label: 'Full' },
  { value: 'short', label: 'Short' },
  { value: 'none', label: 'Hidden' }
]
const TIME_OPTIONS: { value: TimeFormat; label: string }[] = [
  { value: 'twelveHour', label: '12 Hours' },
  { value: 'twentyFourHour', label: '24 Hours' },
  { value: 'none', label: 'Hidden' }
]
const labelOf = <T extends string>(opts: { value: T; label: string }[], v: T): string =>
  opts.find((o) => o.value === v)?.label ?? opts[0].label

function PickerRow<T extends string>({
  glyph,
  label,
  ariaLabel,
  value,
  options,
  onPick
}: {
  glyph: IconName
  label: string
  ariaLabel: string
  value: T
  options: { value: T; label: string }[]
  onPick: (v: T) => void
}): React.JSX.Element {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLButtonElement>(null)
  return (
    <div className={s.row}>
      <span className={s.leading}>
        <Icon name={glyph} size={16} />
      </span>
      <span className={s.label}>{label}</span>
      <button ref={ref} type="button" className={s.trigger} aria-label={ariaLabel} onClick={() => setOpen(true)}>
        <span className={s.value}>{labelOf(options, value)}</span>
        <Icon name="chevrons-up-down" size={12} />
      </button>
      {open && (
        <PickerMenu open={open} onDismiss={() => setOpen(false)} triggerRef={ref}>
          {options.map((o) => (
            <PickerOption
              key={o.value}
              selected={o.value === value}
              onClick={() => {
                onPick(o.value)
                setOpen(false)
              }}
            >
              {o.label}
            </PickerOption>
          ))}
        </PickerMenu>
      )}
    </div>
  )
}

/** The datetime property's per-view Format section — Date · (conditional) Day · Time. The Day row
 *  (weekday) reveals only for the worded date formats (short/full); Relative and the numeric formats
 *  carry no weekday. Time stays visible under Relative (it gates the "at <clock>" rendering). */
export function DateTimeEditor({
  style,
  onChange
}: {
  style: ColumnStyle
  onChange: (patch: Partial<ColumnStyle>) => void
}): React.JSX.Element {
  const dateFmt: DateFormat = style.date_format ?? 'full'
  const showDay = dateFmt === 'short' || dateFmt === 'full'
  return (
    <div className={s.section}>
      <span className={s.heading}>Format</span>
      <PickerRow
        glyph="calendar-days"
        label="Date"
        ariaLabel="Date format"
        value={dateFmt}
        options={DATE_OPTIONS}
        onPick={(v) => onChange({ date_format: v })}
      />
      <Reveal open={showDay} fill>
        <PickerRow
          glyph="calendar-days"
          label="Day"
          ariaLabel="Weekday format"
          value={style.weekday ?? 'none'}
          options={WEEKDAY_OPTIONS}
          onPick={(v) => onChange({ weekday: v })}
        />
      </Reveal>
      <PickerRow
        glyph="clock"
        label="Time"
        ariaLabel="Time format"
        value={style.time_format ?? 'none'}
        options={TIME_OPTIONS}
        onPick={(v) => onChange({ time_format: v })}
      />
    </div>
  )
}
```

The CSS (mirror the URLEditor `linkRow` spacing — leading glyph + label + trailing control):

```ts
// dateTimeEditor.css.ts
import { style } from '@vanilla-extract/css'
import { vars as colorVars } from '../../design-system/tokens/color.css'
import { text } from '../../design-system/tokens/typography.css'

const c = colorVars.color
export const section = style({ display: 'flex', flexDirection: 'column' })
export const heading = style([text.caption.emphasized, { color: c.label.secondary, padding: '6px 8px 2px' }])
export const row = style({ display: 'flex', alignItems: 'center', gap: '8px', minHeight: '28px', padding: '4px 8px' })
export const leading = style({ display: 'inline-flex', color: 'var(--label-secondary)' })
export const label = style([text.body.standard, { flex: '1 1 auto', color: c.label.primary }])
export const trigger = style({
  display: 'inline-flex',
  alignItems: 'center',
  gap: '4px',
  border: 'none',
  background: 'none',
  padding: 0,
  cursor: 'default',
  selectors: { '&&': { color: 'var(--label-secondary)' } }
})
export const value = style([text.body.standard, { selectors: { '&&': { color: 'var(--label-secondary)' } } }])
```

In `PropertiesPane.tsx`, render the editor in the datetime branch (replace the blank `<div style={{ minHeight: 8 }} />` for datetime — add a branch BEFORE the fallback):

```tsx
) : def.type === 'datetime' ? (
  <DateTimeEditor style={resolvedStyle(def.id)} onChange={(patch) => saveColumnStyle(def.id, patch)} />
) : (
  <div style={{ minHeight: 8 }} />
)}
```

Add `import { DateTimeEditor } from './DateTimeEditor'`.

- [ ] **Step 4: Run tests + typecheck + build + full suite**

Run: `npx vitest run src/renderer/src/Components/Detail/dateTimeEditor.test.tsx src/renderer/src/Components/Detail/propertiesPane.datetime.test.tsx && env -u ELECTRON_RUN_AS_NODE npm run typecheck && env -u ELECTRON_RUN_AS_NODE npm run build && npx vitest run`
Expected: all PASS, GREEN, build OK, full suite green.

- [ ] **Step 5: Commit**

```bash
git add src/renderer/src/Components/Detail/DateTimeEditor.tsx src/renderer/src/Components/Detail/dateTimeEditor.css.ts \
  src/renderer/src/Components/Detail/PropertiesPane.tsx \
  src/renderer/src/Components/Detail/dateTimeEditor.test.tsx \
  src/renderer/src/Components/Detail/propertiesPane.datetime.test.tsx
git commit -m "feat(properties): datetime Format editor — Date/Day/Time pickers, conditional weekday row

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Post-functional UIX pass + docs reconciliation

**Files:**
- Modify: `.claude/Features/Properties.md`, `.claude/Features/Views.md`, `.claude/History.md`

- [ ] **Step 1: UIX review (mandatory, post-green — Review-Discipline).** With the app running (`env -u ELECTRON_RUN_AS_NODE npm run dev`), open Properties → a Date property → verify: the three rows, the Day row's disclosure reveal on switching Date to/from short/full, center-aligned picker options, capitalized labels, and that the table cell re-renders on each pick. Adjudicate the Nathan-eyeball items (week cutoff, Day glyph, far-end fallback). Fix any UIX gaps before closeout.

- [ ] **Step 2: Reconcile the stale docs.** In `Properties.md`, the Pending "Display Formats" + "Per-Type Editor Panes" claims that formats "ride through as foreign keys until a UI reads them" are false — the renderer reads them and the editor now sets them. Restate as shipped (the datetime Format editor: per-view Date/Day/Time, `column_styles`). In `Views.md`, note `column_styles` now carries `weekday`. Do NOT restate exact code values (docs name, code holds exacts).

- [ ] **Step 3: History entry.** Add a concise `History.md` entry: the datetime property Format editor (per-view, second surface to the column menu), the decoupled weekday dimension, the reshaped `full`, and the `relative` format.

- [ ] **Step 4: Commit** (bundle docs with the feature per house rule)

```bash
git add .claude/Features/Properties.md .claude/Features/Views.md .claude/History.md
git commit -m "docs: datetime Format editor + weekday/relative — reconcile Properties/Views, log History

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage** (against the decision log):
- A-1/A-2 (per-view second surface) → Task 6. A-3 (thread node, not path; Set divergence) → Task 5. A-4 (saveViewAdopting) → Task 5.
- B-1 (date options/order, full weekday-free) → Tasks 2, 6. B-2 (time options) → Task 6. B-3/B-4 (Day dimension, conditional, disclosure) → Tasks 1, 6. B-5 (Time always visible) → Task 6. B-6 (column-menu parity + STYLE_VALUES) → Task 4. B-7 (glyphs, centered, capitalized) → Task 6.
- C-1/C-1a (formatDate decomposition + both switch arms) → Tasks 2, 3. C-2 (existing full drops weekday) → Task 2. C-3 (relative spec) → Task 3. C-4 (Cell forwards weekday) → Task 2. C-4a (CalendarPicker coercion) → Task 3.
- D-1 (nexus default out of scope) → not built (Prospect). D-2 (docs) → Task 7. D-3 (`last_edited_time` excluded) → holds (PropertiesPane `props` filter drops reserved ids; verified).
- E-1 (preserve on collapse) → satisfied by design: hiding the Day row never writes; the stored `weekday` persists in `column_styles` untouched. E-2 (formatDate ripple) → Task 2 (optional param keeps callers green; only Cell opts in). E-3 (test fixtures) → Tasks 2, 3. E-4 (cellMenu shares styleMenuItems) → free via Task 4. E-5 (backward read) → free (looseObject + catch, Task 1 test covers it).

**2. Placeholder scan:** The only non-code step is Task 5's component test harness ("follow the existing propertiesPane.test.tsx") — that's a real, existing reference file, not a TBD. Everything else carries complete code.

**3. Type consistency:** `WeekdayFormat`/`WEEKDAY_FORMATS` (`'long'|'short'|'none'`), `DateFormat` (+`'relative'`), `ColumnStyle.weekday`, `formatDate(iso, dateFormat, timeFormat, weekday?, now?)`, `saveColumnStyle(propId, patch)`, `DateTimeEditor({style, onChange})` — consistent across Tasks 1–6. `clockOf` (Task 2) is reused by `formatRelative` (Task 3).

**Note for the executor:** Tasks 1–3 share one green gate (the `'relative'` union member can't compile without its switch arms) — implement them consecutively and commit once at the end of Task 3, as written.
