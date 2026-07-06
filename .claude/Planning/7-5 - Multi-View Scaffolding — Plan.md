# Multi-View Scaffolding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the multi-view scaffolding on the existing SavedView layer — the SettingsPane rename, the menu consolidation, the ViewDropdown switcher + ViewPane navigation dropdown, the shared two-door ViewSettings editor, view creation, and the G-1/G-2 invariant machinery — per the review-certified Decision Log.

**Architecture:** Files-canonical Electron app: main owns fs behind typed IPC envelopes; the renderer store refetches via `load()` after writes. All new sidecar keys ship BOTH allowlist sides (zod codec + node fields + readNexus branches). Entry-mint in `store.select` is the sole view-mint site; every sentinel-holding writer adopts through one shared helper.

**Tech Stack:** Electron 42 · React 19 · TS 6 · zod · vanilla-extract · Zustand · Vitest (`npx vitest run <file>`) · `npm run typecheck` (the only type gate).

**Spec:** `.claude/Planning/7-5 - Multi-View Scaffolding — Decision Log.md` (entry ids like G-1 cited throughout) + `…— Reconciliation Report.md` (the grounding companion). Re-read both before starting.

## Global Constraints

- Biome auto-formats on write — never hand-align; if an Edit fails on whitespace, re-read and retry.
- `npm run typecheck` green before every commit; Vitest for pure logic (`src/shared`, pipeline, model files).
- Colors only as tokens from `design-system/tokens` — never literal hex/rgb in components.
- No code comments except non-obvious "why" (1–2 lines max). No meta-commentary in UI copy ever (`Guidelines/UI-Copy.md`) — unbuilt panes render blank chrome.
- UI action labels Title-Case ("New View", "Hide Title"). No keyboard shortcuts anywhere (none are approved).
- Commit per task with explicit file paths (`git add <paths>` — never `git add -A`; parallel sessions are common). End commit messages with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Long-running builds/tests/agents: `run_in_background: true`.
- Main-process (`src/main`, `src/preload`) changes need a full dev-process restart — neither HMR nor ⌘R picks them up. Renderer CSS hot-reloads; renderer TSX HMRs.
- GUI launch needs `ELECTRON_RUN_AS_NODE` unset: `env -u ELECTRON_RUN_AS_NODE npm run dev`.
- UI self-verification via CDP screenshots (launch with `--remote-debugging-port`, capture `Page.captureScreenshot`, Read the PNG). Never type into existing pages of the live Nexus — create a throwaway page/container to drive. Native menus can't be driven by CDP: Nathan manually passes those surfaces.
- After each task ships green, re-read this plan against what landed; rewrite affected later tasks before dispatching the next.

---

### Task 1: The Rename — SettingsPane + settingsPane.css.ts

Everything else lands on settled names (H-6). Pure rename + import updates; zero behavior change.

**Files:**
- Rename: `Pommora/src/renderer/src/Components/Detail/ViewPane.tsx` → `SettingsPane.tsx` (component `ViewPane` → `SettingsPane`)
- Rename: `Pommora/src/renderer/src/Components/Detail/viewPane.css.ts` → `settingsPane.css.ts`
- Modify (imports only): `Toolbar/Toolbar.tsx`, `Components/Detail/SettingsDropdown.tsx`, `Components/Detail/paneDnd.tsx`, `Components/Detail/InlineEditHeader.tsx`, `Components/Detail/PropertiesPane.tsx`, `Components/Detail/DashIcon.tsx`, `Components/Detail/HiddenPane.tsx`, `Components/Detail/URLEditor.tsx`, `Components/Detail/StatusEditor.tsx`, `Components/Detail/OptionEditor.tsx`

**Interfaces:**
- Produces: `SettingsPane` (same props: none), `settingsPane.css.ts` exporting the identical style names. Every later task imports these names.

- [ ] **Step 1:** `git mv` both files; update the component name, its JSDoc ("The Collection/Set settings menu…"), and all 10 importer paths (`from './viewPane.css'` → `'./settingsPane.css'`; `from '../Components/Detail/viewPane.css'` in Toolbar accordingly; `SettingsDropdown` renders `<SettingsPane />`).
- [ ] **Step 2:** Run: `npm run typecheck` → PASS. Launch dev, CDP-screenshot the settings dropdown open → identical to before.
- [ ] **Step 3:** Commit: `refactor: rename ViewPane to SettingsPane, freeing the ViewPane name`

### Task 2: Menu Consolidation — Tones, AccessoryButton, TopRow, BottomRow (H-2, H-4)

**Files:**
- Modify: `Pommora/src/renderer/src/design-system/components/menu/menu.css.ts`
- Modify: `Pommora/src/renderer/src/design-system/components/menu/Menu.tsx`
- Modify: `Pommora/src/renderer/src/design-system/components/menu/index.ts`
- Modify: `Pommora/src/renderer/src/Components/Detail/settingsPane.css.ts` (delete the five clones + tone re-declarations; keep surface-local styles)
- Modify: `Pommora/src/renderer/src/Components/Detail/SettingsPane.tsx`, `PropertiesPane.tsx`, `HiddenPane.tsx` (consume the new primitives)

**Interfaces:**
- Produces (menu.css.ts): `dropdownRowTitle` (label-control title tone, dropdown-scoped — applied per-surface, NEVER on the base `item`, which the sidebar shares), `headingLabel`, `actionLabel`, `accessoryButton`, `accessoryGhostRest`, `accessoryHiddenRest` (+ `accessoryRevealParent` hook), `topRowPad`, `paneSeparator`, and the hoisted **`anchor`** (+ `--dropdown-origin`) moved verbatim from settingsPane.css.ts (H-3) — Toolbar and every dropdown import it from the menu home; settingsPane.css.ts drops its copy.
- Produces (Menu.tsx): `AccessoryButton` component `{ icon: IconName; size: number; ariaLabel: string; box?: number; onClick: () => void }`; `MenuPaneTopRow` `{ label: string; onBack: () => void; trailing?: ReactNode }` (‹ chevron + heading + optional trailing, WITH its flush separator); `MenuBottomRow` `{ leading?: ReactNode; trailing?: ReactNode }` (separator above, leading pinned left / trailing pinned right).

- [ ] **Step 1:** Record the before count: `git ls-files -z 'Pommora/src/renderer/src/design-system/components/menu/*' 'Pommora/src/renderer/src/Components/Detail/settingsPane.css.ts' | xargs -0 grep -vcE '^\s*(//|/\*|\*|$)'` (sum it).
- [ ] **Step 2:** Add to `menu.css.ts`:

```ts
export const dropdownRowTitle = style({ color: c.label.control })
export const headingLabel = style({ color: c.label.secondary })
export const actionLabel = style({ color: c.label.tertiary })

export const accessoryButton = style({
  width: 'var(--accessory-box, 16px)',
  height: 'var(--accessory-box, 16px)',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  border: 'none',
  background: 'none',
  padding: 0,
  cursor: 'default',
  borderRadius: '5px',
  transition: `background ${duration.fast} ${easing.standard}`,
  selectors: {
    '&&': { color: c.label.tertiary },
    '&:hover': { background: c.state.hover }
  }
})
export const accessoryGhostRest = style({
  opacity: 'var(--state-ghost)',
  transition: `opacity ${duration.fast} ${easing.standard}, background ${duration.fast} ${easing.standard}`,
  selectors: { '&:hover': { opacity: 1 } }
})
export const accessoryRevealParent = style({})
export const accessoryHiddenRest = style({
  opacity: 0,
  transition: `opacity ${duration.fast} ${easing.standard}, background ${duration.fast} ${easing.standard}`,
  selectors: {
    [`${accessoryRevealParent}:hover &`]: { opacity: 'var(--state-ghost)' },
    [`${accessoryRevealParent}:hover &:hover`]: { opacity: 1 }
  }
})
export const topRowPad = style({ paddingBlock: 'var(--top-row-block, 2px)', minHeight: 0, color: c.label.secondary })
export const paneSeparator = style({ marginBottom: 'var(--top-row-block, 2px)' })
```

(`duration`/`easing` import from `../../tokens/motion`. The `&&` keeps every accessory out-ranking `.app-toolbar button`'s 0,1,1 tone. **Accessory boxes preserve current per-consumer sizes — NO box change** (eye · `+` · palette = 16px; TopRow ⊕/⋮ · Options `+` = 20px); each existing consumer passes its exact box via the `box` prop, so Task 2 is a truly pixel-identical refactor. `topRowPad`/`paneSeparator` carry the CURRENT ViewPane values verbatim — `label.secondary` tone + the `topRowBlock: 2` rhythm — the TopRow scheme reuses existing colors and sizes, never re-tunes.)
- [ ] **Step 3:** Add to `Menu.tsx`:

```tsx
export function AccessoryButton({ icon, size, ariaLabel, box, onClick, className }: {
  icon: IconName; size: number; ariaLabel: string; box?: number
  onClick: () => void; className?: string
}): React.JSX.Element {
  return (
    <button
      type="button"
      className={cx(s.accessoryButton, className)}
      style={box ? ({ '--accessory-box': `${box}px` } as CSSProperties) : undefined}
      aria-label={ariaLabel}
      onClick={(e) => { e.stopPropagation(); onClick() }}
    >
      <Icon name={icon} size={size} />
    </button>
  )
}

export function MenuPaneTopRow({ label, onBack, trailing }: {
  label: string; onBack: () => void; trailing?: ReactNode
}): React.JSX.Element {
  return (
    <>
      <MenuTopRow label={label} onClick={onBack} className={s.topRowPad} trailing={trailing} />
      <MenuSeparator flush className={s.paneSeparator} />
    </>
  )
}

export function MenuBottomRow({ leading, trailing }: { leading?: ReactNode; trailing?: ReactNode }): React.JSX.Element {
  return (
    <>
      <MenuSeparator flush />
      <div className={s.bottomRow}>
        {leading}
        <span style={{ flex: '1 1 auto' }} />
        {trailing}
      </div>
    </>
  )
}
```

with `export const bottomRow = style([flushAffordance, { display: 'flex', alignItems: 'center', paddingRight: 0 }])` in menu.css.ts. Export all from `index.ts`.
- [ ] **Step 4:** Refactor the three panes: delete `topRowAction`/`rowPlus`/`optionsAdd`/`eyeButton`/`paletteButton`/`groupAdd` + `topRowPad`/`paneSeparator` + COLOR's `headingLabel`/`actionLabel`/`iconHover` from `settingsPane.css.ts` (keep `dragHighlight`, `eyeHidden`, `allRow`, and the eye-glyph-swap selectors rewritten against `accessoryButton`); replace every `backHeader`/`actionHeader`/`pendingPane` header pair and HiddenPane's inline pair with `MenuPaneTopRow`; replace the six button call sites with `AccessoryButton` (+ variant classes; eye keeps its rest/hover glyph swap spans; palette wraps rows in `accessoryRevealParent`).
- [ ] **Step 5:** `npm run typecheck` → PASS. CDP-screenshot: settings dropdown root, Properties list (hover a registry row's +), Visibility pane (hover an eye), an option editor (hover a chip row's palette) → pixel-identical behavior.
- [ ] **Step 6:** Re-run the Step-1 count command; report the code-only before/after diff in the task summary.
- [ ] **Step 7:** Commit: `refactor: consolidate menu tones, AccessoryButton, TopRow/BottomRow schemes into menu.css`

### Task 3: Segmented Single-Button Collapse (H-1)

**Files:**
- Modify: `Pommora/src/renderer/src/design-system/components/Segmented-Controls/Segmented.tsx`

**Interfaces:**
- Produces: `SegmentedSymbol`/`SegmentedButton` render a SINGLE segment as a standalone pill (no divider, uniform radius) — `segments.length === 1` is first-class; internal core branches on a `segmented = segments.length > 1` boolean.

- [ ] **Step 1:** In the core, derive `const segmented = segments.length > 1` and gate the divider/segment-edge styling on it (single segment gets the pill's full rounding + the plain hover state). Do not change the multi-segment render path.
- [ ] **Step 2:** `npm run typecheck` → PASS. CDP-screenshot the toolbar (trio + back/forward unchanged).
- [ ] **Step 3:** Commit: `refactor: Segmented renders a single segment as a standalone control`

### Task 4: Icon Registrations (H-8)

**Files:**
- Modify: `Pommora/src/renderer/src/design-system/symbols/index.tsx`
- Create: `Pommora/src/renderer/src/design-system/symbols/custom/ListRounded.tsx`, `custom/CardsGrid.tsx`
- Modify: `Pommora/src/renderer/src/Components/Detail/PropertyTypes.tsx`
- Modify: `.claude/Features/Icons.md` (the assignments)

**Interfaces:**
- Produces registry names: `table`, `calendar-days`, `chart-gantt`, `chevrons-up-down`, `layout-panel-left`, `text-align-justify`, `list-rounded` (custom), `cards-grid` (custom). `PropertyTypeIcon` accepts `PropertyType | 'title'`; `'title'` → `text-align-justify`.

- [ ] **Step 1:** Register the six Lucide icons (`Table, CalendarDays, ChartGantt, ChevronsUpDown, PanelLeft → LayoutPanelLeft, TextAlignJustify` — use the exact lucide-react export names; check `node_modules/lucide-react/dist/lucide-react.d.ts` if an import errors).
- [ ] **Step 2:** Author the two customs as registry-conforming SVG components (24×24 viewBox, `stroke="currentColor"`, `strokeWidth 1.75`, no fill): `ListRounded` = three text lines with leading circles (filled 2px-radius dots swapped for stroked circles); `CardsGrid` = a 2×3 grid of 2:3-aspect rounded rects. Register as `'list-rounded'` / `'cards-grid'`.
- [ ] **Step 3:** In `PropertyTypes.tsx`, widen `PropertyTypeIcon` to `{ type: PropertyType | 'title' }` with `'title'` resolving `{ label: 'Title', icon: 'text-align-justify' }` from a sibling const (Title isn't a `PropertyType`; don't force it into the map's key type).
- [ ] **Step 4:** Update `Features/Icons.md` (add Title's row + the view-type glyph table). `npm run typecheck` → PASS.
- [ ] **Step 5:** Commit: `feat: register view-type + control glyphs; Title gets text-align-justify at source`

### Task 5: Shared Model — ViewType Roster, `format`, the Mint Seam (D-6, D-8, E-2)

**Files:**
- Modify: `Pommora/src/shared/views.ts`
- Modify: `Pommora/src/shared/views.test.ts` (EXISTS — 10 live tests; append the new `describe` blocks, never rewrite the file)
- Modify: `Pommora/src/renderer/src/Detail/Views/pipeline/*` only if a `board` reference exists (grep first — none expected)

**Interfaces:**
- Produces: `VIEW_TYPES = ['table', 'list', 'cards', 'gallery', 'calendar', 'timeline']`; `SavedView.format?: 'standard' | 'compact'` (+ codec `format: z.enum(VIEW_FORMATS).optional()`); `mintNewView(name: string, schema: PropertyDefinition[]): SavedView` — the `+`-creation mint (title-only). The per-type seam is a named mint-fields function per type (a future type adds its function + a `switch` in `mintNewView`) — no lookup-table ceremony. Both mints share one `mintBase` (id sentinel · icon · type · structural group) and both emit **icon `'table'`** — legacy `'tablecells'` sidecars still render via the `iconNameOr(view.icon, 'table')` fallback at every consumer.

- [ ] **Step 1:** APPEND failing tests to the existing `views.test.ts` (reuse its imports where present; the blocks below are additions, not a file body):

```ts
import { describe, expect, it } from 'vitest'
import { mintDefaultView, mintNewView, savedView } from './views'
import { RESERVED_PROPERTY_ID } from './properties'

const schema = [{ id: 'prop_a' }, { id: 'prop_b' }] as never[]

describe('savedView codec', () => {
  it('coerces an unknown type to table and round-trips format', () => {
    const v = savedView.parse({ id: 'view_x', name: 'B', type: 'board', property_order: [], hidden_properties: [], format: 'compact' })
    expect(v.type).toBe('table')
    expect(v.format).toBe('compact')
  })
  it('drops an unknown format value', () => {
    const v = savedView.parse({ id: 'view_x', name: 'B', type: 'table', property_order: [], hidden_properties: [], format: 'huge' })
    expect(v.format).toBeUndefined()
  })
})

describe('mintNewView', () => {
  it('mints title-only: schema ids and all three tiers hidden', () => {
    const v = mintNewView('Untitled', schema)
    expect(v.name).toBe('Untitled')
    expect(v.type).toBe('table')
    expect(v.hidden_properties).toEqual(['prop_a', 'prop_b', RESERVED_PROPERTY_ID.tier1, RESERVED_PROPERTY_ID.tier2, RESERVED_PROPERTY_ID.tier3])
  })
})

describe('mintDefaultView', () => {
  it('stays all-shown', () => {
    expect(mintDefaultView(schema).hidden_properties).toEqual([])
  })
})
```

Run: `npx vitest run src/shared/views.test.ts` → FAIL (mintNewView undefined; 'board' still in enum makes the coercion test fail).
- [ ] **Step 2:** Implement: swap `VIEW_TYPES`; add `const VIEW_FORMATS = ['standard', 'compact'] as const` + `format` on the interface and codec; add:

```ts
const mintBase = (name: string) => ({
  id: DEFAULT_VIEW_ID,
  name,
  icon: 'table',
  type: 'table' as const,
  group: { kind: 'structural' as const }
})

function tableMintFields(schema: PropertyDefinition[]): Pick<SavedView, 'property_order' | 'hidden_properties'> {
  return {
    property_order: [RESERVED_PROPERTY_ID.title],
    hidden_properties: [
      ...schema.map((d) => d.id),
      RESERVED_PROPERTY_ID.tier1,
      RESERVED_PROPERTY_ID.tier2,
      RESERVED_PROPERTY_ID.tier3
    ]
  }
}

export function mintNewView(name: string, schema: PropertyDefinition[]): SavedView {
  return { ...mintBase(name), ...tableMintFields(schema) }
}
```

and refactor `mintDefaultView` onto the same base: `{ ...mintBase('Table'), property_order: [RESERVED_PROPERTY_ID.title, ...schema.map((d) => d.id)], hidden_properties: [] }`. (No existing test asserts a mint icon, and the codec passes any icon string through — the `collection-with-status.json` fixture's `'tablecells'` is unaffected.) When appending Step 1's blocks, drop any import line the file already declares — the blocks are additions, never a file body.

- [ ] **Step 3:** `npx vitest run src/shared/views.test.ts` → PASS. `grep -rn "'board'" Pommora/src` → only historical test fixtures if any; fix them. `npm run typecheck` → PASS.
- [ ] **Step 4:** Commit: `feat(model): six-type roster, SavedView format, per-type mint seam with title-only creation`

### Task 6: Sidecar + Node Allowlists — `open_in` Rename, `view_button`, `view_style` (F-1, F-2)

**Files:**
- Modify: `Pommora/src/shared/schemas.ts`, `Pommora/src/shared/types.ts`
- Modify: `Pommora/src/main/readNexus.ts`
- Create: `Pommora/src/shared/schemas.containerConfig.test.ts`

**Interfaces:**
- Produces on-disk keys: `open_in: 'full-page' | 'page-preview'` (collection only; legacy `window`→`full-page`, `compact`→`page-preview` coerced on read), `view_button: 'icon' | 'labeled'`, `view_style: 'dropdown' | 'toolbar'` (both sidecars). Node fields consumed by every later task: `CollectionNode.openIn?/viewButton?/viewStyle?`, `SetNode.viewButton?/viewStyle?` (types exported as `OpenIn`, `ViewButton`, `ViewStyle` from `shared/types.ts`).

- [ ] **Step 1:** Failing tests: legacy coercion (`{open_in:'window'}` parses to `'full-page'`), unknown value drops to undefined, `view_button`/`view_style` round-trip on both sidecar schemas.
- [ ] **Step 2:** Implement in `schemas.ts`:

```ts
const OPEN_IN_LEGACY: Record<string, string> = { window: 'full-page', compact: 'page-preview' }
const openIn = z.preprocess(
  (v) => (typeof v === 'string' ? (OPEN_IN_LEGACY[v] ?? v) : v),
  z.enum(['full-page', 'page-preview']).optional().catch(undefined)
)
const viewButton = z.enum(['icon', 'labeled']).optional().catch(undefined)
const viewStyle = z.enum(['dropdown', 'toolbar']).optional().catch(undefined)
```

wired into `pageCollectionSidecar` (`open_in: openIn, view_button: viewButton, view_style: viewStyle`) and `pageSetSidecar` (`view_button`, `view_style`). In `types.ts`: export the three unions + add the optional node fields. In `readNexus.ts`: populate them in `readPageCollection`/`readSet` by coercing the three raw `meta.<key>` values through per-field helpers exported from schemas.ts (e.g. `coerceOpenIn(raw)` = the same zod piece) — the `parseViews` precedent. Do NOT switch readNexus to whole-sidecar zod parsing; its raw cached read walk is deliberate (the perf law).
- [ ] **Step 3:** `npx vitest run src/shared/schemas.containerConfig.test.ts` → PASS. `npm run typecheck` → PASS.
- [ ] **Step 4:** Commit: `feat(model): container config keys end-to-end on the read walk (open_in rename + view_button + view_style)`

### Task 7: Container-Config Write Path + Serialization Wraps (F-2, G-2)

**Files:**
- Create: `Pommora/src/main/crud/containerConfig.ts`
- Modify: `Pommora/src/main/index.ts` (new handler + wrap the three views handlers), `Pommora/src/main/io/activeViews.ts`, `Pommora/src/main/io/viewOrders.ts`, `Pommora/src/preload/index.ts`, `Pommora/src/preload/index.d.ts` (or wherever `window.nexus` types live — follow the existing pattern)

**Interfaces:**
- Produces: `window.nexus.container.configure(containerPath: string, kind: 'collection' | 'set', patch: ContainerConfigPatch): Promise<{ ok: true } | { ok: false; error: string }>` where `ContainerConfigPatch = { open_in?: OpenIn; view_button?: ViewButton; view_style?: ViewStyle }` (exported from `shared/types.ts`). Rejects `open_in` on a `set`.

- [ ] **Step 1:** `containerConfig.ts` — an RMW mirroring `crud/views.ts`: read sidecar by kind, spread the patch's defined keys, `writeSidecar` with `modified_at`; `fail('invalid', …)` when `open_in` arrives for a set.
- [ ] **Step 2:** Handler in `index.ts` under the views block, the envelope pattern, body wrapped: `serializeOnFile(c.folder, () => setContainerConfig(...))`. In the same pass wrap the existing three: `views:save`/`views:reorder`/`views:delete` bodies each become `serializeOnFile(c.folder, () => saveView/reorderViews/deleteView(...))` (import already present at index.ts:13). In `io/activeViews.ts` and `io/viewOrders.ts`, wrap each write function's read-merge-write in `serializeOnFile(<its json path>, …)`.
- [ ] **Step 3:** Preload surface `container: { configure: … }` + type. Extend the existing `io/activeViews.test.ts` + `io/viewOrders.test.ts` for the serialized shape (two overlapping writes both land). `npm run typecheck` + `npx vitest run src/main/io` → PASS.
- [ ] **Step 4:** Restart the dev process. Sanity via CDP console: `await window.nexus.container.configure('<throwaway collection path>', 'collection', { view_button: 'labeled' })` → `{ok:true}`; confirm the sidecar JSON gained the key and its other keys survived.
- [ ] **Step 5:** Commit: `feat(ipc): container-config write path; serialize views + pointer-file writes on the file lock`

### Task 8: Creation-Seed in createContainer (G-1 site 1)

**Files:**
- Modify: `Pommora/src/main/mutate.ts` (the `createContainer` case)

**Interfaces:**
- Consumes: `createFolderEntity`'s `extra` param; `mintDefaultView` from `@shared/views`; `newId` from `./ids`; `VIEW_ID_PREFIX`.
- Produces: every app-created Collection/Set is born with `views: [defaultView]` carrying a REAL `view_<ulid>` id.

- [ ] **Step 1:** In the `createContainer` case, resolve the schema the new container inherits (a new collection has no assignments yet → `[]`; a set inherits but the default mint uses `[]` property refs safely — mint with `[]`), and add:

```ts
extra.views = [{ ...mintDefaultView([]), id: `${VIEW_ID_PREFIX}${newId()}` }]
```

(One line; `mintDefaultView([])` = Title-first, structural group. A fresh container has no pages, so the empty-schema order is exact, and the pipeline appends later-assigned props implicitly — columns.ts pass 2.)
- [ ] **Step 2:** Restart dev. Create a Collection and a Set in the throwaway area via the UI; read both sidecars → each has one `view_<ulid>` view. `npm run typecheck` → PASS.
- [ ] **Step 3:** Commit: `feat(main): creation-seed — containers are born with their default view on disk`

### Task 9: Entry-Mint + the Adopt-Only Helper (G-1 site 2)

**Files:**
- Create: `Pommora/src/renderer/src/Detail/Views/viewMint.ts`, `Pommora/src/renderer/src/Detail/Views/useActiveView.ts`
- Modify: `Pommora/src/renderer/src/store.ts` (the `select` collection/set cases)
- Modify: `Pommora/src/renderer/src/Detail/Views/Table/TableView.tsx` (`persistView`), `Pommora/src/renderer/src/Components/Detail/HiddenPane.tsx` (`save`)

**Interfaces:**
- Produces (`viewMint.ts`; `source` is a real `CollectionNode | SetNode` everywhere — no bespoke structural types):
  - `ensureContainerView(source: CollectionNode | SetNode, schema: PropertyDefinition[], refetch: () => Promise<void>): void` — no-op when `views` is non-empty; else registers/reuses the in-flight mint.
  - `pendingViewMint(containerId: string): Promise<string> | undefined`
  - `saveViewAdopting(source: CollectionNode | SetNode, view: SavedView, refetch: () => Promise<void>): Promise<{ ok: true; id: string } | { ok: false; error: string }>` — the ONE writer every surface calls: sentinel + mint-in-flight → await the minted id and save against it; sentinel + no mint (mint errored) → plain save (the recovery mint); real id → plain save. On a sentinel save it also writes `activeViews.set(source.id, id)` so the writer's edits stay on the view the user sees. Duplicate deliberately does NOT use this helper (Task 12) — it must not touch activeViews; that boundary earns its one-line "why" comment.
- Produces (store slice — the cross-surface view-switch wire): `activeViews: Record<string, string>` on the session store, hydrated inside `load()` (an `activeViews.get()` alongside `nexus.state()`), plus the action `setActiveView(containerId: string, viewId: string): Promise<void>` = the IPC write + a slice update (no tree reload). This is load-bearing: the per-machine pointer is NOT in `NexusTree`, and without shared state a ViewPane switch would repaint neither the table nor the button (each surface would hold its own stale local fetch). `saveViewAdopting`'s sentinel adoption routes through `setActiveView` so the slice never drifts from disk.
- Produces (`useActiveView.ts`): `useActiveView(source: CollectionNode | SetNode, schema: PropertyDefinition[]): { activeViewId: string | undefined; view: SavedView }` — a store-selector hook (`useSession((s) => s.activeViews[source.id])` + `pickView`), no effect, reactive to every switch. HiddenPane refactors onto it in Step 3 (its local `activeViewId` state + fetch effect delete; the post-adopt write-back is `setActiveView`); TableView's bundled effect drops its activeViews fetch and reads the hook; Tasks 10/11/12's surfaces are born on it.

- [ ] **Step 1:** Implement `viewMint.ts`:

```ts
const inFlight = new Map<string, Promise<string>>()

export const pendingViewMint = (containerId: string): Promise<string> | undefined => inFlight.get(containerId)

export function ensureContainerView(source, schema, refetch): void {
  if ((source.views?.length ?? 0) > 0 || inFlight.has(source.id)) return
  const mint = (async () => {
    const res = await window.nexus.views.save(source.path, source.kind, mintDefaultView(schema))
    if (!res.ok) throw new Error(res.error)
    await refetch()
    return res.id
  })()
  inFlight.set(source.id, mint)
  void mint.finally(() => inFlight.delete(source.id))
}

export async function saveViewAdopting(source, view, refetch) {
  let toSave = view
  if (view.id === DEFAULT_VIEW_ID) {
    const minted = await pendingViewMint(source.id)?.catch(() => undefined)
    if (minted) toSave = { ...view, id: minted }
  }
  const res = await window.nexus.views.save(source.path, source.kind, toSave)
  if (res.ok && toSave.id === DEFAULT_VIEW_ID) await window.nexus.activeViews.set(source.id, res.id)
  await refetch()
  return res
}
```

(Exact signatures per Interfaces; `refetch` is the store's `load`.)
- [ ] **Step 2:** In `store.ts` `select`, after the synchronous `set(...)` in the `collection` and `set` cases, resolve the node (`findCollection` / `findSet` from `./Detail/Scope`) and its schema (`collection.properties ?? []`; a set via `findCollectionForSet`), then `ensureContainerView(node, schema, load)` — the case stays synchronous for render; the mint is a fired side-effect. Depth gating is structural: `findSet` only lands selectable sets.
- [ ] **Step 3:** TableView: `persistView` becomes `void saveViewAdopting(source, mergeOverrides(liveView, …patch…), load)`. HiddenPane: `save` collapses to `const res = await saveViewAdopting(source, { ...view, ...patch }, load); if (!res.ok) await window.nexus.showError(res.error)` — its hand-rolled `wasSentinel` block deletes (with the sentinel-adoption comment moving to `saveViewAdopting`). Note: `activeViews` local state — HiddenPane keeps `setActiveViewId(res.id)` when the id changed.
- [ ] **Step 4:** Verification: delete `views` from a throwaway container's sidecar by hand → select it in the app → within a beat the sidecar regains one `view_<ulid>` entry (entry-mint), the table renders throughout (sentinel). Resize a column DURING the beat (CDP) → exactly ONE view exists after settle (adopt-only). `npm run typecheck` + `npx vitest run` (full) → PASS.
- [ ] **Step 5:** Commit: `feat(store): entry-mint as the sole view-mint site with the shared adopt-only writer`

### Task 10: ViewDropdown Button + Context Menu (B-1..B-7)

**Files:**
- Create: `Pommora/src/renderer/src/Toolbar/ViewDropdown.tsx`, `Pommora/src/renderer/src/Toolbar/viewDropdown.css.ts`
- Modify: `Pommora/src/renderer/src/Toolbar/Toolbar.tsx`, `Pommora/src/renderer/src/Toolbar/toolbar.css`
- Create: `Pommora/src/main/viewButtonMenu.ts`; Modify: `Pommora/src/main/index.ts`, `Pommora/src/preload/index.ts` (+ types)

**Interfaces:**
- Consumes: `SegmentedSymbol`/`SegmentedButton` (single-segment), `pickView`, `mintDefaultView`, node fields `viewButton`/`viewStyle`, `iconNameOr`, `window.nexus.container.configure`.
- Produces: `<ViewDropdown />` rendered in Toolbar left of the trio ONLY when the selection is a Collection/depth-1 Set; `window.nexus.viewButtonMenu(current: { viewButton: ViewButton; viewStyle: ViewStyle }): Promise<'toggle-title' | 'style-dropdown' | 'style-toolbar' | null>`.

- [ ] **Step 1:** Create `Pommora/src/main/returningMenu.ts` — the returning-picker plumbing exists hand-rolled in SIX main files (`optionMenu`, `propertyMenu`, `cellMenu`, `columnMenu`, `tableMenu`, `calloutMenu` — each with its own `let acted` promise dance); the three menus this plan adds must not be occurrences 7–9:

```ts
export function popReturningMenu<A>(
  win: BrowserWindow,
  buildItems: (pick: (a: A) => () => void) => MenuItemConstructorOptions[]
): Promise<A | null> {
  return new Promise((resolve) => {
    let acted = false
    const items = buildItems((a) => () => {
      acted = true
      resolve(a)
    })
    Menu.buildFromTemplate(items).popup({
      window: win,
      callback: () => {
        if (!acted) resolve(null)
      }
    })
  })
}
```

`viewButtonMenu.ts` then declares only its template: `[{ label: current.viewButton === 'labeled' ? 'Hide Title' : 'Show Title', click: pick('toggle-title') }, { label: 'Style', submenu: [{ label: 'Dropdown', type: 'checkbox', checked: current.viewStyle === 'dropdown', click: pick('style-dropdown') }, { label: 'Toolbar', type: 'checkbox', checked: current.viewStyle === 'toolbar', click: pick('style-toolbar') }] }]`. IPC handler + preload mirror `propertyMenu`'s shape. The six existing sites consolidate onto the helper in Task 14's simplifier lane with Nathan's green light — not silently here (caveat for that pass: `propertyMenu`'s destroy case runs an async confirm dialog before resolving, so it either keeps its own dance or the helper gains an async-resolve escape hatch).
- [ ] **Step 2:** `ViewDropdown.tsx`: derive the container node from `selection` + `tree` (the SettingsPane's own lookup pattern); `const { view } = useActiveView(node, schema)` (the Task 9 store-selector hook — the glyph follows every switch reactively); glyph `iconNameOr(view.icon, 'table')`. Render by `node.viewButton ?? 'icon'`: icon → `SegmentedSymbol` one segment; labeled → `SegmentedButton` one segment with the view name in an `OverflowScroll` span inside the fixed-width label (knobs in viewDropdown.css.ts: `BUTTON.iconPadX`, `BUTTON.labeledWidth`, `BUTTON.labeledPadX`). `viewStyle` branch: `if ((node.viewStyle ?? 'dropdown') === 'toolbar') { /* ViewBar slot — renders the same button until it exists */ }` — a real branch, one comment allowed (the seam's why). `onContextMenu` → `viewButtonMenu` → on action, `container.configure(node.path, node.kind, …)` then `load()`. Anchor + pane mount follow Toolbar's settings pattern (`useExitPresence`, own anchor from the menu home, notch to the button center).
- [ ] **Step 3:** Toolbar: render `<ViewDropdown />` in a cluster left of the trio; add the shared spacing knob to `toolbar.css` (`--toolbar-gap: 10px`) consumed between clusters; ride math reads the button's measured width var (the `--trio-w` ResizeObserver pattern, a `--viewdd-w`).
- [ ] **Step 4:** Restart dev (main changed). CDP: select a collection → button shows table glyph; select a page/context → button absent. Toggle labeled via sidecar hand-edit → fixed-width labeled button, long name overflow-scrolls. Nathan's manual pass: right-click menu items + checkmarks + persistence.
- [ ] **Step 5:** `npm run typecheck` → PASS. Commit: `feat(toolbar): per-container ViewDropdown with native presentation menu`

### Task 11: ViewPane — the Navigation Dropdown (C-1..C-7, E-1, E-3)

**Files:**
- Create: `Pommora/src/renderer/src/Toolbar/ViewPane.tsx` (+ styles in `viewDropdown.css.ts` or a sibling `viewPane.css.ts` under `Toolbar/`)
- Modify: `Pommora/src/renderer/src/Toolbar/ViewDropdown.tsx` (mounts it)
- Modify: `Pommora/src/shared/types.ts` + `Pommora/src/main/readNexus.ts` (`personalization.openViewOnCreate`)

**Interfaces:**
- Consumes: `MenuSurface`, `MenuItem` + `dropdownRowTitle`, `MenuSeparator`, `MenuBottomRow`, `AccessoryButton`, `PaneSlider`, `PaneDnd` in a **flat mode through its existing seams** — `RowShell`/`usePaneDrag` only work inside the `<PaneDnd>` provider (paneDnd.tsx:277 throws outside), and the provider's snapshot requires both region rects, so the ViewPane registers its ONE list element under both region keys (the synthetic single region) and passes the injectable `slot` prop (paneDnd.tsx:56). `paneDndModel` gains one honest union member — `{ kind: 'reorder-flat'; id: string; toIndex: number }` — returned by the injected flat slot fn (built on `slotInGroup`, sidebarDndModel.ts:78) and decoded in ViewPane's `onDrop` via `nextOrder` (:64) → `views:reorder`. Zero new slot math; one new drop kind; the two-region property model untouched. Also `Reveal` + motion tokens (the create fold), `saveViewAdopting`… views list from `node.views ?? [sentinel]`.
- Produces: the open dropdown — rows (click: `setActiveView(node.id, v.id)` — the store action, no `load()`; the table and button repaint through the slice — then close; chevron: push slot B → ViewSettings (Task 12 fills it; until then slot B renders blank chrome)); drag-reorder persisting `views:reorder`; footer `+` (mint `mintNewView('Untitled', schema)` → `views.save` → `load()` → fold the new row in; navigate only when `personalization.openViewOnCreate`) and `…` (chrome, no menu).

- [ ] **Step 1:** Add `openViewOnCreate?: boolean` to `Personalization` + the `bool(p.openViewOnCreate)` branch in `readPersonalization`.
- [ ] **Step 2:** Build the pane: `MenuSurface` + own anchor/notch; rows `MenuItem` (icon `iconNameOr(v.icon,'table')` at label-secondary, title span `dropdownRowTitle`, trailing chevron `AccessoryButton`-free — a plain `Icon chevron-right` in `side`); active row `selected`; row click = `await setActiveView(node.id, v.id)` (the store action — the table and the button glyph repaint through the slice subscription) + close; chevron click stops propagation and pushes. Reorder rides `RowShell` + the drag mechanics with the flat slot computation (per Consumes) → `window.nexus.views.reorder(node.path, node.kind, orderedIds)` + `load()`. Footer `MenuBottomRow` leading `+` / trailing `…` AccessoryButtons. Create: disable the `+` while a create is pending; the newest row wraps in its OWN `Reveal` with `open` flipped true on mount (a mount-in fold — `Reveal`'s block-toggle precedent doesn't transfer directly to an appended row), on `duration.base`/`easing.standard`.
- [ ] **Step 3:** CDP: two views in a container → open pane, click row 2 → table re-renders on view 2, pane closed, activeViews.json updated. `+` → "Untitled" folds in at bottom, title-only when opened (only Title column). Drag row 1 below row 2 → sidecar order flips. `npm run typecheck` → PASS.
- [ ] **Step 4:** Commit: `feat(views): ViewPane navigation dropdown — switch, reorder, create`

### Task 12: ViewSettings — the Shared Editor, Both Doors (D-1..D-11)

> **BUILD GATE (Nathan):** before writing any ViewSettings code, re-read the Decision Log §D entries AND pull the Figma design — `get_screenshot`/`get_design_context` on node `307:5248` (Design page) for the ViewSettings frame (icon+title header, the 3×2 rectangular-tile grid, Layout ›/Format ⇅ rows). Confirm the grid geometry + tile proportions against the frame, then STOP and confirm the UIX directives with Nathan before implementing.

**Files:**
- Create: `Pommora/src/renderer/src/Components/Detail/ViewSettings.tsx`, `viewSettings.css.ts`
- Create: `Pommora/src/main/viewItemMenu.ts` (⋮ Duplicate/Delete, returning pattern); Modify: `Pommora/src/main/index.ts`, `Pommora/src/preload/index.ts`
- Modify: `Pommora/src/renderer/src/Toolbar/ViewPane.tsx` (full door in slot B), `Pommora/src/renderer/src/Components/Detail/SettingsPane.tsx` (Layout entry → flat door; Configuration entry + Open In row)
- Modify: `Pommora/src/renderer/src/Detail/Views/Table/TableView.tsx` (root `data-format`)

**Interfaces:**
- Consumes: `MenuPaneTopRow`, `AccessoryButton`, `InlineEditHeader` (or its input-field pieces) for icon+title, `PickerMenu`, `saveViewAdopting`, `PropertyTypeIcon`-style glyphs via the registry, `window.nexus.viewItemMenu(name: string): Promise<'view:duplicate' | 'view:delete' | null>`.
- Produces: `ViewSettings({ source, view, door: 'full' | 'flat', onBack: () => void })`:
  - Header: `MenuPaneTopRow` label = `door === 'full' ? 'Views' : 'Settings'`; trailing ⋮ AccessoryButton only on `full`.
  - Icon square (IconPicker stub wiring point, blank body) + editable title (`saveViewAdopting` on commit; empty commit keeps prior name).
  - The 3×2 grid: `VIEW_TYPES` order Table·Cards·List·Gallery·Calendar·Timeline; tiles = rounded rects (~4:3; knobs `GRID.edgePadX/Y`, `GRID.cellGapX/Y`, `GRID.cellRadius: 6`, 2px border `separator.border`, selected `var(--accent)`), glyph-only at `label-tertiary` (`table`/`cards-grid`/`list-rounded`/`layout-dashboard`/`calendar-days`/`chart-gantt`); only the Table tile clickable (others no-op at full weight); click persists `{ type }` via `saveViewAdopting`.
  - Below (table type): `full` door only — Layout leaf row (`MenuItem` "Layout" + chevron pushing to blank chrome with `MenuPaneTopRow('Settings')`); both doors — the Format row: label "Format", trailing detail (current value, `detail` + `side`) + `chevrons-up-down`; click opens the dual-wired picker (macOS: a returning native two-option menu rides `viewItemMenu`'s pattern in `viewFormatMenu`; else `PickerMenu` with Standard/Compact); pick persists `{ format }` via `saveViewAdopting` — no visual change (no CSS binds).
  - ⋮ menu: Duplicate → insert a copy (new id via sentinel save: `saveViewAdopting(source, { ...view, id: DEFAULT_VIEW_ID }, load)` would adopt-mint — WRONG: duplicate must not touch activeViews; instead `window.nexus.views.save(source.path, source.kind, { ...view, id: DEFAULT_VIEW_ID })` then `views:reorder` placing it directly after the original, then `load()`); Delete → `views:delete` + close the dropdown (H-5/D-3), disabled (muted `actionLabel`, no-op) when `source.views.length <= 1` or the view is the sentinel.
- TableView root element gains `data-format={view.format ?? 'standard'}` — the Compact CSS's future hook, zero rules bind.

- [ ] **Step 1:** `viewItemMenu.ts` (Duplicate/Delete; Delete carries no confirm — it's one view) + `viewFormatMenu` (Standard/Compact two-option) — both are ~4-line templates over `popReturningMenu` (Task 10), never their own plumbing; handlers + preload.
- [ ] **Step 2:** Build `ViewSettings` per the interface; wire the FULL door as ViewPane's slot B (level-2; Layout leaf = level-3 in a nested PaneSlider — PropertiesPane's nesting precedent). Sizing (C-6): extend `PaneSlider` with an optional `maxWidth` (a `max-width` on `slotContent`, the `maxHeight` pattern); levels 1–2 share `minWidth 225` + one shared `maxWidth` knob + `maxHeight 375` (the existing pane's precedent); level-3 omits the shared max and may carry its own.
- [ ] **Step 3:** Wire the FLAT door: SettingsPane's `layout` entry opens `ViewSettings({ door: 'flat', view: activeView })` (active view via `useActiveView`); its `MenuPaneTopRow` back label reads "Settings". Add the `configuration` entry above Properties (icon `sliders-horizontal`, leaf = `MenuPaneTopRow('Settings')` + the Open In row — label "Open In", trailing detail + chevrons-up-down, dual-wired picker persisting via `container.configure` — on a Set the write targets `findCollectionForSet(...).path` with kind 'collection'). Root order per A-3. Group/Filter/Sort leafs: `MenuPaneTopRow` + blank body (the `— pending` captions die here).
- [ ] **Step 4:** TableView `data-format` attribute.
- [ ] **Step 5:** CDP: chevron → editor (‹ Views), rename view, re-type stays table, Format pick persists `format` in sidecar with zero visual change, Layout → blank leaf (‹ Settings), flat door from SettingsPane shows the same editor minus ⋮/leaf, Open In persists on the collection sidecar (also when set from a Set's pane), duplicate lands after the original with the same name, delete closes the dropdown and the table falls back. Nathan's manual pass on the native pickers. `npm run typecheck` → PASS.
- [ ] **Step 5a (H-7 clip check — before commit):** with the pane SCROLLED (enough rows to engage the slot's `overflowY`), open each floating surface — the Format `PickerMenu`, the ⋮ menu path, the IconPicker wiring point — and CDP-confirm each renders fully outside all three clip layers (MenuSurface `overflow:hidden`, PaneSlider viewport, the scrolled slot) via the body portal.
- [ ] **Step 6:** Commit: `feat(views): ViewSettings two-door editor — type grid, Format, Configuration + Open In`

### Task 13: Docs Reconcile + Meta-Commentary Kill (I-2, H-10)

**Files:**
- Modify: `.claude/Features/Views.md` (five→six roster ×3, §View Settings naming: SettingsPane/ViewSettings/ViewDropdown/ViewPane vocabulary, the new keys + mint rules), `.claude/Features/PageSets.md` (only if it names the old pane), `.claude/Features/Icons.md` (already touched in Task 4 — verify), `.claude/Handoff.md` (Next Session refs), `.claude/History.md` (one entry for the cycle's locked decisions)
- Sweep: the whole renderer for meta-commentary strings

**Steps:**
- [ ] **Step 1:** Rewrite the stale doc passages as durable truth (no correction framing). Confirm `Features/Views.md` describes: six types, the ViewDropdown/ViewPane/ViewSettings surfaces, `format`, `view_button`/`view_style`, `open_in`'s new enum, entry-mint + creation-seed, adopt-only.
- [ ] **Step 2:** Dispatch a subagent (`run_in_background`): grep the renderer for `— pending`, `yet.`, `coming soon`, placeholder captions; blank every build-status caption (keep genuine error/empty-data copy: "Schema unavailable.", "Property not found.", "No properties yet."). It returns the file:line list + edits; verify each yourself.
- [ ] **Step 3:** `npm run typecheck` → PASS. CDP-screenshot the three known ex-caption surfaces (nav dropdown, G/F/S leafs) → blank chrome.
- [ ] **Step 4 (I-1):** Confirm with Nathan that his Nexus repo gitignores `.nexus/activeViews.json` + `viewOrders.json` (per-machine siblings) — an external-repo prerequisite for the switcher; flag it in the session summary if unconfirmed.
- [ ] **Step 5:** Commit: `docs: reconcile Views/Handoff/History to the multi-view surfaces; blank all meta-commentary`

### Task 14: Review Gates (the loop, per Review-Discipline)

- [ ] **Step 1:** Dispatch `code-simplifier` on the full working-tree diff (`run_in_background`) — required before completion. Verify its edits yourself; fold.
- [ ] **Step 2:** Dispatch `comment-killer-agent` on the diff. Verify; fold.
- [ ] **Step 3:** Dispatch `build-breaking-agent` post-green: attack the invariant machinery (mint races, adopt paths, serialization), the allowlist pairs, and the clip contexts (every floating surface in the panes against all three clip layers, scrolled state included — H-7). Verify each finding against the code before folding.
- [ ] **Step 4:** `npm run typecheck` + `npx vitest run` → PASS. Full CDP visual pass, then **Nathan's UIX review of the actual working UI — mandatory before closeout** (functional-green ≠ done). His native-menu pass rides this.
- [ ] **Step 5:** `/handoff`.

## Task-Order Dependencies

1 → 2 → 3 (names → consolidation → control) · 4 anytime before 10 · 5 → 6 → 7 → 8 → 9 (model → allowlists → write path → seed → mint) · 10 → 11 → 12 (button → pane → editor) · 13, 14 last. Tasks 4 and 5 may run in parallel sessions ONLY with explicit-path staging; everything else serializes.
