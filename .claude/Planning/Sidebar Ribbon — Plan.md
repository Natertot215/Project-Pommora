# Sidebar Ribbon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Obsidian-like ribbon — a fixed icon strip pinned to the left edge of the sidebar — that switches the sidebar between Collections / Contexts / Agenda modes, with Homepage/Nav/Settings as launcher icons.

**Architecture:** The ribbon is a `position:absolute` strip *outside* the scrolling `.sidebar` element (so scroll can't move it or cross it); the sidebar content gets a left inset. A new `personalization.sidebarMode` (synced) drives which mode the content column renders, cross-fading via the existing `useExitPresence`. Homepage is a `selection` (routes the main pane, no mode change); Agenda mode renders a real read-only list via a new lazy `agenda:list` IPC. The current one-tree Sidebar splits into per-mode components, each with its own `SidebarDnd`.

**Tech Stack:** Electron 42 (CJS main/preload) · React 19 · TypeScript 6 · Zustand · vanilla-extract (`.css.ts`) + plain CSS (`Sidebar.css`) · PommoraDND (`design-system/interactions/drag.tsx`) · Vitest (jsdom + `createRoot`/`act`, NOT `@testing-library`).

**Spec:** `.claude/Planning/Sidebar Ribbon — Decision Log.md` (review-certified). Read it first.

## Global Constraints

- **Branch:** all work on `sidebar-ribbon` (experimental). Never commit to `main`.
- **Main owns fs**; renderer reaches it only through the typed preload IPC. IPC returns `{ ok: true, … } | { ok: false, error }` and never throws across the boundary.
- **`src/shared/types.ts` is the cross-process contract** — no fs, no React there.
- **Never expensive work "on every X"** — agenda reads are lazy/on-demand (mode-gated IPC), NOT folded into the `readNexus` tree walk.
- **Colors** authored as hex, aliased from `design-system/tokens` — never `rgb()`/`rgba()`, never hand-rolled.
- **New source files are PascalCase** (`Ribbon.tsx`). Ribbon *layout* CSS co-locates in `Sidebar.css` (it coordinates with existing `.sidebar`/`.surface-glass` rules).
- **Gates (all must pass before each commit):** `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (two `tsc` passes) · `npx vitest run` · `npm run build`.
- **Never run Biome** — it auto-formats on write. If an Edit fails on whitespace, re-read and retry.
- **Main/preload changes need a full dev restart** (no HMR); CM6/extension changes need ⌘R. Renderer/CSS HMR is live.
- **User Sections CRUD is OUT OF SCOPE** — a separate later spec. Do not build section create/rename/delete here.

---

### Task 1: Personalization schema — `sidebarMode` + `ribbonOrder`

Add the two synced knobs that drive the ribbon. `sidebarMode` is renderer-read (no DOM apply-map row needed — the `default` case already no-ops it); `ribbonOrder` is the persisted icon order. Both follow the exact `favoriteIcons`/`setPlacement` pattern.

**Files:**
- Modify: `src/shared/types.ts` (the `Personalization` interface, ~line 85)
- Modify: `src/main/readNexus.ts` (`readPersonalization`, lines 79-105)
- Test: `src/main/readNexus.test.ts` (create if absent; else add cases)

**Interfaces:**
- Produces: `type SidebarMode = 'collections' | 'contexts' | 'agenda'`; `Personalization.sidebarMode?: SidebarMode`; `Personalization.ribbonOrder?: string[]`.

- [ ] **Step 1: Create the branch**

```bash
cd "Pommora" && git checkout -b sidebar-ribbon
```

- [ ] **Step 2: Add the type + fields**

In `src/shared/types.ts`, above the `Personalization` interface, add:

```typescript
/** Which surface the sidebar content column renders. Homepage is a selection, not a mode. */
export type SidebarMode = 'collections' | 'contexts' | 'agenda'
```

Inside `Personalization`, after `subSetPlacement`, add:

```typescript
  /** The sidebar ribbon's active mode (which content the column shows). Absent = 'collections'. */
  sidebarMode?: SidebarMode
  /** Ribbon icon order below the pinned Homepage — bare icon keys, in display order. */
  ribbonOrder?: string[]
```

- [ ] **Step 3: Write the failing coercion test**

In `src/main/readNexus.test.ts`, add (adapt imports to the file's existing harness; `readPersonalization` is module-private — if it isn't exported, export it for the test, matching how other private readNexus helpers are tested, or test via the public read if that's the house pattern):

```typescript
import { readPersonalization } from './readNexus'

test('coerces a valid sidebarMode + ribbonOrder', () => {
  const p = readPersonalization({ sidebarMode: 'agenda', ribbonOrder: ['agenda', 'collections'] })
  expect(p.sidebarMode).toBe('agenda')
  expect(p.ribbonOrder).toEqual(['agenda', 'collections'])
})

test('drops an invalid sidebarMode and empty/garbage ribbonOrder', () => {
  const p = readPersonalization({ sidebarMode: 'bogus', ribbonOrder: [1, '', 'contexts'] })
  expect(p.sidebarMode).toBeUndefined()
  expect(p.ribbonOrder).toEqual(['contexts'])
})
```

- [ ] **Step 4: Run it, verify it fails**

Run: `cd "Pommora" && npx vitest run src/main/readNexus.test.ts`
Expected: FAIL (`sidebarMode` undefined-vs-'agenda', or `readPersonalization` not exported).

- [ ] **Step 5: Implement the coercion**

In `readPersonalization` (readNexus.ts), add a local validator and two return fields. After the `placement` helper (line 82):

```typescript
  const mode = (v: unknown): SidebarMode | undefined =>
    v === 'collections' || v === 'contexts' || v === 'agenda' ? v : undefined
  const ribbonOrder = Array.isArray(p.ribbonOrder)
    ? p.ribbonOrder.filter((v): v is string => typeof v === 'string' && v.length > 0)
    : []
```

In the returned object (after `subSetPlacement`):

```typescript
    sidebarMode: mode(p.sidebarMode),
    ribbonOrder: ribbonOrder.length ? ribbonOrder : undefined
```

Add `SidebarMode` to the `@shared/types` import at the top of readNexus.ts. If `readPersonalization` wasn't exported, add `export`.

- [ ] **Step 6: Run gates**

Run: `cd "Pommora" && npx vitest run src/main/readNexus.test.ts && env -u ELECTRON_RUN_AS_NODE npm run typecheck`
Expected: tests PASS, typecheck 0 errors.

- [ ] **Step 7: Commit**

```bash
cd "Pommora" && git add src/shared/types.ts src/main/readNexus.ts src/main/readNexus.test.ts && git commit -m "feat(ribbon): add sidebarMode + ribbonOrder personalization knobs"
```

---

### Task 2: Agenda read path — shared collect helper + `agenda:list` IPC + preload bridge

Serve Tasks + Events to the renderer through a **lazy, on-demand IPC** (called only when Agenda mode is active) — never the tree walk. Extract the existing `collectAgenda` walk (currently private in `src/main/index/build.ts:239`) into a shared module both the index builder and the new handler use (DRY), returning a renderer-facing `AgendaEntry[]`.

**Files:**
- Create: `src/main/agenda/collectAgenda.ts` (extracted walk)
- Modify: `src/main/index/build.ts` (import the extracted walk instead of the local copy)
- Modify: `src/shared/types.ts` (add `AgendaEntry` + `AgendaListResult`)
- Modify: `src/main/index.ts` (add the `agenda:list` handler)
- Modify: `src/preload/index.ts` (add `agenda.list()`)
- Test: `src/main/agenda/collectAgenda.test.ts`

**Interfaces:**
- Produces: `interface AgendaEntry { id; title; kind: 'task' | 'event'; icon?; dueAt?; startAt?; endAt? }`; `window.nexus.agenda.list(): Promise<{ ok: true; tasks: AgendaEntry[]; events: AgendaEntry[] } | { ok: false; error: string }>`.
- Consumes: `AgendaItemData`/`AgendaData` internal shape from `build.ts:239-284` (moved, not rewritten).

- [ ] **Step 1: Add the shared renderer type**

In `src/shared/types.ts`:

```typescript
/** A read-only agenda entity for the sidebar list (main → renderer). Dates are ISO strings or absent. */
export interface AgendaEntry {
  id: string
  title: string
  kind: 'task' | 'event'
  icon?: string
  dueAt?: string
  startAt?: string
  endAt?: string
}
```

- [ ] **Step 2: Extract `collectAgenda` into a shared module**

Create `src/main/agenda/collectAgenda.ts` by moving the `collectAgenda` function body from `build.ts:239-284` verbatim, exporting it, and having it return `{ tasks: AgendaEntry[]; events: AgendaEntry[] }` (map its `common`/`item` fields to `AgendaEntry` — set `kind: 'task'|'event'`, carry `icon`, `dueAt` for tasks, `startAt`/`endAt` for events; drop `properties`/`tiers`/`modifiedAt` which the list doesn't need). Preserve the sidecar-detection + zod-parse + skip-on-error logic exactly. Keep the file's imports (`readdir`, `readFile`, `pathExists`, `join`, `SIDECAR_FILENAME`, `AGENDA_SUFFIX`, `agendaTask`, `agendaEvent`).

- [ ] **Step 3: Point build.ts at the extracted walk**

In `build.ts`, delete the now-moved `collectAgenda` and import the shared one. Because the index builder needs the *full* `AgendaItemData` (properties/tiers/modifiedAt) for the SQLite upserts, keep build.ts's own richer walk if the extraction would lose those fields — **decision: extract only if the index columns are covered; otherwise leave build.ts's copy and write a lean sibling `collectAgendaEntries` in the new module.** Prefer a lean sibling to avoid regressing the index (the index needs more fields than the list). Confirm by reading `build.ts:270-281` — if the upsert needs `properties`/`modifiedAt`, do NOT collapse the two; write the lean list walk fresh (~35 lines, same sidecar/parse pattern).

- [ ] **Step 4: Write the failing test**

Create `src/main/agenda/collectAgenda.test.ts` — build a temp nexus dir with a `Tasks/_taskconfig.json` + one `.task.json` and an `Events/_eventconfig.json` + one `.event.json`, then assert the walk returns them (use the file's node `fs`/`os.tmpdir` pattern; mirror any existing main-side fs test in the repo for setup/teardown):

```typescript
test('collects tasks and events from their sidecar folders', async () => {
  // …write temp fixture: Tasks/_taskconfig.json, Tasks/Buy milk.task.json {id,due_at},
  //   Events/_eventconfig.json, Events/Standup.event.json {id,start_at,end_at}
  const { tasks, events } = await collectAgendaEntries(root)
  expect(tasks.map((t) => t.title)).toContain('Buy milk')
  expect(tasks[0].kind).toBe('task')
  expect(events.map((e) => e.title)).toContain('Standup')
})
```

- [ ] **Step 5: Run it, verify it fails, then implement**

Run: `cd "Pommora" && npx vitest run src/main/agenda/collectAgenda.test.ts`
Expected: FAIL (module/function missing) → implement the lean walk from Step 3 → rerun → PASS.

- [ ] **Step 6: Add the IPC handler**

In `src/main/index.ts`, near the other read handlers, add (adapt `sessionRoot()`/current-nexus accessor to how existing handlers get the root):

```typescript
ipcMain.handle('agenda:list', async () => {
  const root = currentNexusRoot()
  if (!root) return { ok: false as const, error: 'No nexus open' }
  try {
    const { tasks, events } = await collectAgendaEntries(root)
    return { ok: true as const, tasks, events }
  } catch (e) {
    return { ok: false as const, error: e instanceof Error ? e.message : String(e) }
  }
})
```

- [ ] **Step 7: Add the preload bridge**

In `src/preload/index.ts`, in the `nexus` object, add:

```typescript
  agenda: {
    list: () => ipcRenderer.invoke('agenda:list')
  },
```

Add the matching type to the preload's exposed API type (wherever `window.nexus` is typed) so the renderer sees `nexus.agenda.list()` returning the envelope with `AgendaEntry[]`.

- [ ] **Step 8: Run gates + commit**

Run: `cd "Pommora" && npx vitest run && env -u ELECTRON_RUN_AS_NODE npm run typecheck && npm run build`

```bash
cd "Pommora" && git add src/main/agenda src/main/index/build.ts src/main/index.ts src/preload/index.ts src/shared/types.ts && git commit -m "feat(ribbon): lazy agenda:list read path for the Agenda sidebar mode"
```

---

### Task 3: The ribbon strip — layout + icons (static, no switching yet)

Build the ribbon as an absolute strip inside `<Surface>`, left of `.sidebar`, with its own `no-drag` + traffic-light offset + 2.5px right border; inset `.sidebar` by the ribbon width. Homepage icon = the nexus photo (reused from NexusHeader). The other five icons render but don't switch yet. Purely additive and visually verifiable.

**Files:**
- Create: `src/renderer/src/Sidebar/Ribbon.tsx`
- Create: `src/renderer/src/Sidebar/NexusPhoto.tsx` (extracted photo control)
- Modify: `src/renderer/src/Sidebar/Sidebar.css` (ribbon rules + `.sidebar` inset)
- Modify: `src/renderer/src/App.tsx` (render `<Ribbon>` inside `<Surface>`, before `<Sidebar>`)
- Test: `src/renderer/src/Sidebar/Ribbon.test.tsx`

**Interfaces:**
- Produces: `<Ribbon />` (reads `personalization.sidebarMode` + `ribbonOrder` from the store; renders Homepage-pinned + ordered launcher icons). `<NexusPhoto size={number} />` (photo span, right-click to change, click selects homepage).

- [ ] **Step 1: Extract `<NexusPhoto>`**

Create `src/renderer/src/Sidebar/NexusPhoto.tsx` holding the photo span + `pickPhoto`/`saveCrop`/`PhotoCropModal` logic from NexusHeader.tsx:32-42,65-67,88. Props: `{ size: number }`. It reads `profileImage` from the tree, renders `<img>` or the `square-dashed` fallback, wires `onContextMenu={pickPhoto}` and (for the ribbon) leaves click handling to the caller. Reuse `assetUrl` + `nexusHeader.css.ts` `.photo` classes or add ribbon-sized variants.

- [ ] **Step 2: Define the ribbon icon registry + `<Ribbon>`**

Create `src/renderer/src/Sidebar/Ribbon.tsx`:

```tsx
import type { SidebarMode } from '@shared/types'
import { Icon } from '@renderer/design-system/symbols'
import { useSession } from '../store'
import { NexusPhoto } from './NexusPhoto'
import './Sidebar.css'

type RibbonKey = 'navigation' | 'agenda' | 'contexts' | 'collections' | 'settings'
const MODE_FOR: Partial<Record<RibbonKey, SidebarMode>> = { collections: 'collections', contexts: 'contexts', agenda: 'agenda' }
const RIBBON_ICON: Record<RibbonKey, string> = {
  navigation: 'map', agenda: 'calendar', contexts: 'layout-grid', collections: 'folder', settings: 'sliders-horizontal'
}
const DEFAULT_ORDER: RibbonKey[] = ['collections', 'contexts', 'agenda', 'navigation', 'settings']

export function Ribbon(): React.JSX.Element {
  const select = useSession((s) => s.select)
  const mode = useSession((s) => s.personalization.sidebarMode ?? 'collections')
  const order = useSession((s) => s.personalization.ribbonOrder)
  const setPersonalization = useSession((s) => s.setPersonalization)
  const keys = (order?.filter((k): k is RibbonKey => k in RIBBON_ICON) ?? DEFAULT_ORDER)
  // Fill in any key missing from a persisted partial order, so a new icon never vanishes.
  for (const k of DEFAULT_ORDER) if (!keys.includes(k)) keys.push(k)

  const onIcon = (k: RibbonKey): void => {
    const m = MODE_FOR[k]
    if (m) setPersonalization('sidebarMode', m) // mode switch (Collections/Contexts/Agenda)
    // navigation/settings: no-op for now (future glass windows)
  }

  return (
    <div className="sidebar-ribbon" role="tablist" aria-label="Sidebar sections">
      <button type="button" className="ribbon-icon ribbon-home" aria-label="Homepage" onClick={() => void select({ kind: 'homepage' })}>
        <NexusPhoto size={22} />
      </button>
      {keys.map((k) => {
        const m = MODE_FOR[k]
        const active = m != null && m === mode
        return (
          <button key={k} type="button" className={active ? 'ribbon-icon ribbon-icon-active' : 'ribbon-icon'} aria-label={k} aria-selected={active} onClick={() => onIcon(k)}>
            <Icon name={RIBBON_ICON[k]} size={18} />
          </button>
        )
      })}
    </div>
  )
}
```

(Icon choices are placeholders → Nathan/Figma tune; `folder`/`calendar`/`layout-grid`/`map`/`sliders-horizontal` are valid Lucide ids.)

- [ ] **Step 3: Ribbon CSS + sidebar inset**

In `src/renderer/src/Sidebar/Sidebar.css`, add (values via existing CSS vars/tokens where they exist; `--ribbon-w` a new local var):

```css
:root { --ribbon-w: 44px; }
.sidebar-ribbon {
  position: absolute;
  left: 0; top: 0; bottom: 0;
  width: var(--ribbon-w);
  padding-top: 46px; /* clear the traffic lights, matching .sidebar */
  display: flex; flex-direction: column; align-items: center; gap: 4px;
  border-right: 2.5px solid var(--separator-border);
  -webkit-app-region: no-drag; /* else icon clicks drag the frameless window */
  z-index: 2;
}
.sidebar { padding-left: calc(var(--ribbon-w) + 10px); } /* inset content past the ribbon */
.ribbon-icon { /* icon button: size, radius, hover via label-control tokens */ }
.ribbon-icon-active { /* the single active-mode highlight */ }
```

Use the real separator/border token name (grep `--separator` in Sidebar.css / tokens); do not hardcode a hex. Confirm `.sidebar`'s existing `padding` (line 32 `46px 10px 12px`) — change only the left value to include the ribbon.

- [ ] **Step 4: Mount `<Ribbon>` in the shell**

In `src/renderer/src/App.tsx`, inside `<Surface>` (line 116), before the sidebar `<Sidebar tree={tree} />` (or before the collapse button), render `{status === 'ready' && tree && <Ribbon />}`. Import `Ribbon`.

- [ ] **Step 5: Write the render test**

Create `src/renderer/src/Sidebar/Ribbon.test.tsx` (jsdom + `createRoot`/`act` house pattern; stub `ResizeObserver` if needed; seed the store with a tree). Assert: the Homepage button renders first; the five launcher buttons render; clicking "collections" calls `setPersonalization('sidebarMode','collections')`; the button whose mode equals the store mode has `ribbon-icon-active`.

- [ ] **Step 6: Run it, verify pass, run gates**

Run: `cd "Pommora" && npx vitest run src/renderer/src/Sidebar/Ribbon.test.tsx && env -u ELECTRON_RUN_AS_NODE npm run typecheck && npm run build`

- [ ] **Step 7: Visual check (Nathan)**

Launch `env -u ELECTRON_RUN_AS_NODE npm run dev`, confirm the ribbon strip sits left with its border, icons don't drag the window, top icon clears the traffic lights. Adjust `--ribbon-w`/icon sizes/gap to Nathan's eye (point to the knobs, don't over-tune).

- [ ] **Step 8: Commit**

```bash
cd "Pommora" && git add src/renderer/src/Sidebar/Ribbon.tsx src/renderer/src/Sidebar/NexusPhoto.tsx src/renderer/src/Sidebar/Ribbon.test.tsx src/renderer/src/Sidebar/Sidebar.css src/renderer/src/App.tsx && git commit -m "feat(ribbon): pinned ribbon strip with launcher icons (static)"
```

---

### Task 4: Mode switching — split Sidebar into modes, cross-fade, drop headings, dissolve NexusHeader

Turn the one-tree `Sidebar` into a mode-switched content column. Extract the Contexts and Collections sections into their own components (each wrapping its own `<SidebarDnd>`), render per `sidebarMode`, cross-fade between them with `useExitPresence`, remove the "Contexts"/"Collections" `SectionHeader`s, and remove the `NexusHeader` mount (its photo now lives in the ribbon; the name already surfaces in `HomepageView` via `DetailScaffold owner.name`, so nothing is lost).

**Files:**
- Create: `src/renderer/src/Sidebar/CollectionsMode.tsx` (Collections + user sections)
- Create: `src/renderer/src/Sidebar/ContextsMode.tsx` (the three tiers)
- Modify: `src/renderer/src/Sidebar/Sidebar.tsx` (become the mode switcher; drop NexusHeader + the two SectionHeaders)
- Modify: `src/renderer/src/Sidebar/Sidebar.css` (cross-fade layering)
- Test: `src/renderer/src/Sidebar/Sidebar.test.tsx` (mode routing)

**Interfaces:**
- Consumes: `personalization.sidebarMode` from the store; `useExitPresence` (`design-system/useExitPresence` — the two-panel pattern from Toolbar.tsx:33-34); `<SidebarDnd>` (Sidebar.tsx:443, tolerates a partial tree).
- Produces: `<CollectionsMode tree … />`, `<ContextsMode tree … />` — each self-contained, own DnD.

- [ ] **Step 1: Extract `<ContextsMode>`**

Create `src/renderer/src/Sidebar/ContextsMode.tsx` holding the current Contexts `<div className="section">` body (Sidebar.tsx:446-463) **minus** the `<SectionHeader label="Contexts" …>` — the three `<TierDisclosure>` + `ContextRow` maps — wrapped in its own `<SidebarDnd tree={tree} …>`. Move `TierDisclosure`, `ContextRow`, `TIER_ICON_KIND` (and their imports) with it, or import them if they're shared. Keep the create action available (Task 8 wires the right-click; for now leave a `newContext` reachable).

- [ ] **Step 2: Extract `<CollectionsMode>`**

Create `src/renderer/src/Sidebar/CollectionsMode.tsx` holding the Collections `<div className="section">` (Sidebar.tsx:465-478) **minus** the `<SectionHeader label={pageCollection.plural} …>`, plus the `userSections` map (480-495, keep their `SectionHeader`s — user-named groups stay), all wrapped in its own `<SidebarDnd>`. Move `CollectionRow`/`SetRow`/`PageRow` or import them.

- [ ] **Step 3: Rewrite `<Sidebar>` as the switcher**

`Sidebar.tsx` returns the `<nav className="sidebar scroll-edge-fade">` (keep the scroll listener + `navRef`), but its body becomes a cross-faded mode switch:

```tsx
const mode = useSession((s) => s.personalization.sidebarMode ?? 'collections')
// Render the active mode; cross-fade the outgoing via useExitPresence per the Toolbar two-panel pattern.
```

Render exactly one mode at rest; during a switch, both the outgoing (via `useExitPresence(mode===X)`) and incoming mount, each absolutely stacked and opacity-faded. `AgendaMode` (Task 5) slots in as the third branch — for this task, its branch can render a placeholder `<div />` until Task 5. Drop the `<NexusHeader …>` block (436-439) entirely.

- [ ] **Step 4: Cross-fade CSS**

In `Sidebar.css`, add the layering for the fade (absolute-stacked mode layers within the scroll content, `opacity` transition on `--duration-base`/`--ease-standard`, the `useExitPresence` closing class fading to 0). Each mode layer owns its own height/scroll; the fade is opacity-only (no layout thrash).

- [ ] **Step 5: Write the mode-routing test**

In `src/renderer/src/Sidebar/Sidebar.test.tsx`: seed the store with a tree + `personalization.sidebarMode='collections'`, assert Collections content renders and Contexts doesn't; set mode to `'contexts'`, assert the swap; assert selecting homepage (a `select({kind:'homepage'})`) does NOT change `personalization.sidebarMode`.

- [ ] **Step 6: Run it + gates**

Run: `cd "Pommora" && npx vitest run src/renderer/src/Sidebar && env -u ELECTRON_RUN_AS_NODE npm run typecheck && npm run build`
Expected: PASS. Fix any test that assumed the old single-tree structure (the reviewer flagged the `SidebarDnd` split — expect existing `sidebarDnd.test.tsx` to need re-scoping to per-mode instances).

- [ ] **Step 7: Visual check (Nathan)** — switch modes, confirm the cross-fade reads clean and each mode scrolls independently under the pinned ribbon.

- [ ] **Step 8: Commit**

```bash
cd "Pommora" && git add src/renderer/src/Sidebar && git commit -m "feat(ribbon): split sidebar into cross-faded Collections/Contexts modes"
```

---

### Task 5: Agenda mode — the read-only Tasks + Events list

Render the real agenda list (from Task 2's IPC) as the third mode. Fetch on mount (mode activation), render Tasks then Events as non-routing rows (display/highlight only — no `SelectionState` kind exists for them).

**Files:**
- Create: `src/renderer/src/Sidebar/AgendaMode.tsx`
- Modify: `src/renderer/src/Sidebar/Sidebar.tsx` (wire the `'agenda'` branch to `<AgendaMode>`)
- Test: `src/renderer/src/Sidebar/AgendaMode.test.tsx`

**Interfaces:**
- Consumes: `window.nexus.agenda.list()` → `{ ok, tasks, events }` of `AgendaEntry[]`.
- Produces: `<AgendaMode />`.

- [ ] **Step 1: Build `<AgendaMode>`**

```tsx
import { useEffect, useState } from 'react'
import type { AgendaEntry } from '@shared/types'
import { Icon } from '@renderer/design-system/symbols'

export function AgendaMode(): React.JSX.Element {
  const [data, setData] = useState<{ tasks: AgendaEntry[]; events: AgendaEntry[] }>({ tasks: [], events: [] })
  useEffect(() => {
    let live = true
    void window.nexus.agenda.list().then((r) => { if (live && r.ok) setData({ tasks: r.tasks, events: r.events }) })
    return () => { live = false }
  }, [])
  const row = (e: AgendaEntry): React.JSX.Element => (
    <div key={e.id} className="agenda-row">
      <Icon name={e.icon ?? (e.kind === 'task' ? 'circle' : 'calendar')} size={16} />
      <span className="agenda-title">{e.title}</span>
    </div>
  )
  const empty = data.tasks.length === 0 && data.events.length === 0
  if (empty) return <div className="agenda-empty">No tasks or events</div>
  return (
    <div className="agenda-mode">
      {data.tasks.map(row)}
      {data.events.map(row)}
    </div>
  )
}
```

Add minimal `.agenda-row`/`.agenda-title`/`.agenda-empty` styles to `Sidebar.css` (label tones from tokens; rows non-interactive for now).

- [ ] **Step 2: Wire it in** — replace the Task-4 placeholder `'agenda'` branch in `Sidebar.tsx` with `<AgendaMode />`.

- [ ] **Step 3: Write the test**

`AgendaMode.test.tsx`: stub `window.nexus.agenda.list` to resolve `{ ok: true, tasks: [{id:'t1',title:'Buy milk',kind:'task'}], events: [{id:'e1',title:'Standup',kind:'event'}] }`, mount, `await` a tick, assert both titles render. Add an empty-state case (`tasks:[],events:[]` → "No tasks or events").

- [ ] **Step 4: Run + gates + commit**

Run: `cd "Pommora" && npx vitest run src/renderer/src/Sidebar/AgendaMode.test.tsx && env -u ELECTRON_RUN_AS_NODE npm run typecheck && npm run build`

```bash
cd "Pommora" && git add src/renderer/src/Sidebar/AgendaMode.tsx src/renderer/src/Sidebar/AgendaMode.test.tsx src/renderer/src/Sidebar/Sidebar.tsx src/renderer/src/Sidebar/Sidebar.css && git commit -m "feat(ribbon): Agenda mode renders the read-only tasks + events list"
```

---

### Task 6: Ribbon icon drag-to-order (persist `ribbonOrder`)

Make the five launcher icons reorder by drag (Homepage stays pinned), persisting the order to `personalization.ribbonOrder`. Reuse the `SortableZone` + `reorder` primitive.

**Files:**
- Modify: `src/renderer/src/Sidebar/Ribbon.tsx`
- Test: `src/renderer/src/Sidebar/Ribbon.test.tsx`

**Interfaces:**
- Consumes: `SortableZone`, `useDragItem`, `reorder` from `design-system/interactions/drag.tsx` (`reorder<T extends {id}>(items, activeId, overId)`).

- [ ] **Step 1: Wrap the launcher icons in a `SortableZone`**

Keep the Homepage button outside the zone (fixed). Put the five icons inside a vertical `SortableZone` (`layout="list"`); each icon uses `useDragItem(key)`. On drop, compute `reorder(keys, activeId, overId)` and `setPersonalization('ribbonOrder', next)`.

- [ ] **Step 2: Test the reorder**

Extend `Ribbon.test.tsx`: call the zone's reorder callback (or test the pure `reorder(keys, 'agenda', 'collections')` result) and assert `setPersonalization('ribbonOrder', …)` fires with the moved order; assert Homepage is never in the reorderable set.

- [ ] **Step 3: Run + gates + visual + commit**

Run: `cd "Pommora" && npx vitest run src/renderer/src/Sidebar/Ribbon.test.tsx && env -u ELECTRON_RUN_AS_NODE npm run typecheck && npm run build`
Visual: drag an icon, confirm it reorders and survives a reload (persisted).

```bash
cd "Pommora" && git add src/renderer/src/Sidebar/Ribbon.tsx src/renderer/src/Sidebar/Ribbon.test.tsx && git commit -m "feat(ribbon): drag-to-order launcher icons, persisted to ribbonOrder"
```

---

### Task 7: Right-click create — "New Collection" / "New Context" (closes Handoff:117)

The removed section headers took the only create affordance. Add a right-click native menu on each mode's content area: "New Collection" in Collections mode, the tier picker ("New Area/Topic/Project") in Contexts mode — reusing the existing `newCollection`/`newContext` (`popCreateMenu`) handlers, just triggered from `onContextMenu` instead of the gone header "+".

**Files:**
- Modify: `src/renderer/src/Sidebar/CollectionsMode.tsx`
- Modify: `src/renderer/src/Sidebar/ContextsMode.tsx`
- Test: extend the respective mode tests

**Interfaces:**
- Consumes: the existing `popCreateMenu`/`newContext`/`newCollection` paths (Sidebar.tsx:409,466 originally).

- [ ] **Step 1: Wire `onContextMenu`** on each mode's root container to call the existing create handler (Collections → `newCollection`; Contexts → the tier `popCreateMenu`). Empty-area right-click, not on a row (rows keep their own menus).

- [ ] **Step 2: Test** — assert an `onContextMenu` on the mode container invokes the create handler (spy/stub the menu call).

- [ ] **Step 3: Run + gates + visual + commit**

Visual: right-click empty space in Collections → "New Collection"; in Contexts → tier create. Confirm you can now make a Context from the sidebar (the Handoff:117 backlog item).

```bash
cd "Pommora" && git add src/renderer/src/Sidebar/CollectionsMode.tsx src/renderer/src/Sidebar/ContextsMode.tsx && git commit -m "feat(ribbon): right-click create for Collections + Contexts (closes context sidebar CRUD gap)"
```

---

### Task 8: Park the subtitle + docs reconciliation

Close out: mark the parked subtitle so it doesn't read as dead code, and reconcile every doc the change made partially false.

**Files:**
- Modify: `src/renderer/src/Sidebar/NexusPhoto.tsx` (or wherever the subtitle field survives) — an intent comment
- Modify: `.claude/Features/Sidebar.md`, `Structure.md`, `Agenda.md`, `Navigation.md`, `Configuration.md`
- Modify: `.claude/History.md` (add the entry)

- [ ] **Step 1: Park the subtitle** — keep the `profileSubtitle` read/field with a one-line comment: `// Parked: subtitle isn't surfaced in the ribbon; retained for the eventual homepage/settings surface.` So a future agent doesn't strip it as dead.

- [ ] **Step 2: Reconcile the docs** (durable facts, no line-counts/version stamps; per the doc-writing rules):
  - **Sidebar.md** — replace the "top to bottom: Nexus header → Contexts → Collections → user sections" framing with the ribbon + modes model; drop the Contexts/Collections heading rows; convert the "Calendar Pin" Pending item to the shipped Agenda mode (read-only list); note right-click create.
  - **Structure.md** — the Homepage entry point is now the ribbon icon (was the Nexus header).
  - **Agenda.md** — narrow "Agenda Surfacing … nothing renders": a read-only sidebar list renders; detail/interactivity stays Pending.
  - **Navigation.md** — the ribbon Navigation icon is another placeholder for the Pending Navigation Popover.
  - **Configuration.md** — `personalization` gains `sidebarMode` + `ribbonOrder`.
  - **History.md** — one concise entry: the ribbon, mode-switching, Agenda read path, NexusHeader dissolve, create-path relocation; note User Sections CRUD split to its own spec.

- [ ] **Step 3: Commit**

```bash
cd "Pommora" && cd .. && git add .claude/Features .claude/History.md "Pommora/src/renderer/src/Sidebar/NexusPhoto.tsx" && git commit -m "docs(ribbon): reconcile Sidebar/Structure/Agenda/Navigation/Configuration + park subtitle"
```

---

### Post-Plan: Functional-green ≠ done

After all tasks pass, a **post-functional UIX review of the actual working ribbon** is mandatory (Review-Discipline). Then `/handoff`. User Sections CRUD is the next spec.

## Build-Time Eyeball Items (flag for Nathan, don't guess)

- Ribbon width (`--ribbon-w`), icon glyphs, icon size, gap, active-highlight treatment, the 2.5px border color token.
- Cross-fade duration/feel (starts from `--duration-base`).
- Agenda row density + whether Tasks/Events get a divider or labels.
- Whether the Homepage ribbon icon shows any pressed/hover affordance (it never shows the *active-mode* highlight — B-1).
