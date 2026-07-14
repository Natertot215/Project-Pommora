# App-Wide Auto-Scroll on Drag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One shared auto-scroll-on-drag module that every Pommora drag surface feeds, replacing the two duplicated per-surface copies and retrofitting the three drag surfaces that never had it.

**Architecture:** A single standalone module owns a singleton `requestAnimationFrame` loop. A drag calls `startAutoScroll({ getPoint, scroller?, dragEl?, axis?, onScrolled? })` at activation and `stopAutoScroll()` at end. The loop resolves ONE fixed scroller at start (explicit, or the axis-aware `findScroller(dragEl, axis)`), then every frame reads the last pointer point, computes edge-proximity velocity from that scroller's rect, and scrolls it — time-dampened, direction-gated, frame-rate-independent (px/second × frame-delta), sub-pixel-accumulated, limit-aware. All tunable numbers live in an `autoscroll.css` `:root` token set read off the drag element once per drag. The pure math is unit-tested; the loop lifecycle is verified against a fake scroller plus live drags.

**Tech Stack:** React 19 + TypeScript renderer, Electron 42, Vitest (jsdom). Pointer Events + `setPointerCapture` drags only (zero native HTML5 DnD). Design tokens via plain-CSS `:root` vars consumed with `var(--…)`.

## Global Constraints

- Colors/tokens: this feature authors NO colors. Numeric tuning tokens live in a new `design-system/interactions/autoscroll.css` (`:root` vars), never scattered JS literals.
- Never do expensive work "on every X": `getComputedStyle` (forces layout) is read ONCE per drag at start and cached — never per frame. `getBoundingClientRect` on the fixed scroller is one rect per frame (unavoidable, cheap, single element).
- No SQLite / no fs / no IPC — this is renderer-only interaction code.
- Files start with a capital letter for NEW source files; this feature adds no new `.tsx`, only a `.css` (kebab is the established design-system CSS convention — `scroll-edge-fade.css`, `table-tokens.css` — so `autoscroll.css` matches its siblings).
- Type gate: `env -u ELECTRON_RUN_AS_NODE npm run typecheck` (two `tsc` passes) is the ONLY type-safety gate. Tests: `npx vitest run`. Full build: `env -u ELECTRON_RUN_AS_NODE npm run build`. Capture the real exit code — a piped `| tail` masks a red suite (`set -o pipefail` or read the summary line).
- Biome auto-formats on write via a PostToolUse hook — write correct code and let it style; never run Biome. If an Edit fails on whitespace, re-read the file and retry.
- Commit staging: stage EXPLICIT file paths per task (parallel sessions share the tree — never `git add -A`). Merge/commit only; do not push.
- All work runs against the real dev app (Nathan's live Nexus). Live-verify by dragging; do not mutate or persist test data.

---

## File Map

- `src/renderer/src/design-system/interactions/autoscroll.ts` — **rewritten.** Was a 41-line pure `findScroller` + `autoScroll` pair consumed inline-per-move. Becomes: axis-aware `findScroller`, a set of pure velocity/ramp/dampen/step/intent helpers, and the singleton `startAutoScroll`/`stopAutoScroll` loop. The old `autoScroll(scroller,x,y)` export is deleted (its logic folds into the loop).
- `src/renderer/src/design-system/interactions/autoscroll.css` — **new.** The four tuning tokens.
- `src/renderer/src/design-system/interactions/autoscroll.test.ts` — **new.** Unit tests for the pure helpers + the loop lifecycle against a fake scroller.
- `src/renderer/src/main.tsx` — **modified.** Register `autoscroll.css` after the token bridge import.
- `src/renderer/src/design-system/interactions/engine.test.ts` — **modified.** Its `autoScroll — edge ramp + limit awareness` describe block (lines 42-95) moves into `autoscroll.test.ts`, rewritten against the new pure API; the `autoScroll` import (line 3) is removed.
- `src/renderer/src/design-system/interactions/engine.tsx` — **modified.** Delete the internal `tick`/`d.raf` auto-scroll loop; drive the module instead.
- `src/renderer/src/SurfacePM/SurfaceView.tsx` — **modified.** Migrate the inline `autoScroll` call onto the module; add a scroll re-resolve.
- `src/renderer/src/Components/Detail/paneDnd.tsx` — **modified.** Same migration.
- `src/renderer/src/MarkdownPM/editor/blockDrag.ts` — **modified.** Delete its independent auto-scroll loop (`EDGE`/`edgeStep`/`tick`/`g.raf`); drive the module with an explicit CM scroller.
- `src/renderer/src/Sidebar/sidebarDnd.tsx` — **modified.** New retrofit: feed the module, re-resolve on scroll.
- `src/renderer/src/Detail/Views/Table/tableDnd.tsx` — **modified.** New retrofit (axis `'y'` — the fix that reaches `.detail-scroll`, not the x-only `.table-view`).
- `src/renderer/src/Detail/Views/Table/bandDnd.tsx` — **modified.** New retrofit.
- `.claude/Features/PommoraDND.md`, `.claude/Features/Interaction.md`, `.claude/History.md` — **modified.** Doc reconciliation on ship.

---

## Task 1: Tokens + pure helpers

The math foundation, fully unit-tested, with the old scroll-and-return-bool `autoScroll` retired in favor of pure velocity functions the loop composes.

**Files:**
- Create: `src/renderer/src/design-system/interactions/autoscroll.css`
- Create: `src/renderer/src/design-system/interactions/autoscroll.test.ts`
- Modify: `src/renderer/src/design-system/interactions/autoscroll.ts` (full rewrite of the helper layer; loop added in Task 2)
- Modify: `src/renderer/src/main.tsx` (register the css)
- Modify: `src/renderer/src/design-system/interactions/engine.test.ts` (remove the relocated autoScroll block)

**Interfaces:**
- Produces: `type Axis = 'x' | 'y' | 'xy'`; `interface Params { edge: number; speed: number; ramp: number; dampenMs: number }`; `interface Intent { up: boolean; down: boolean; left: boolean; right: boolean }`; `scrollableInAxis(overflowX, overflowY, dims, axis): boolean`; `findScroller(el: HTMLElement | null, axis?: Axis): HTMLElement | null`; `edgeVelocity(lo: number, hi: number, p: number, params: Params): number`; `dampen(elapsedMs: number, dampenMs: number): number`; `clampToLimit(v: number, pos: number, max: number): number`; `stepPixels(v: number, dtMs: number, frac: number): { px: number; frac: number }`; `gateIntent(intent: Intent, vx: number, vy: number): { vx: number; vy: number }`.

- [ ] **Step 1: Write the token file**

Create `src/renderer/src/design-system/interactions/autoscroll.css`:

```css
/* ============================================================================
   AUTO-SCROLL TOKENS — the single tunable source for the app-wide drag
   auto-scroll loop (design-system/interactions/autoscroll.ts). Read once off
   the drag element at drag start (never per frame). A surface may override any
   of these on its own element or an ancestor (e.g. `.sidebar { --autoscroll-speed }`).
   ============================================================================ */
:root {
  --autoscroll-edge: 48px; /* band from a container edge where auto-scroll engages */
  --autoscroll-speed: 840px; /* px/SECOND at the true edge (≈ the old 14px/frame @60fps, now frame-rate-independent) */
  --autoscroll-ramp: 2; /* proximity ramp exponent — 2 = quadratic (gentle entry, fast at the edge) */
  --autoscroll-dampen-ms: 300ms; /* time-dampening: speed eases from 0 over this window from drag start */
}
```

- [ ] **Step 2: Rewrite the helper layer of `autoscroll.ts`**

Replace the ENTIRE current contents of `src/renderer/src/design-system/interactions/autoscroll.ts` with the helper layer below. (The loop — `startAutoScroll`/`stopAutoScroll`/`tick` — is appended in Task 2; leave it out for now so this task's tests target pure functions only.)

```ts
// App-wide auto-scroll-on-drag. One singleton rAF loop (Task 2) scrolls a FIXED container — resolved
// once at drag start — toward whichever edge the pointer holds near: frame-synced, proximity-ramped,
// time-dampened, direction-gated, limit-aware. Every drag surface feeds it a point + a scroller; no
// surface re-implements the loop. Tuning lives in autoscroll.css, read off the drag element once per
// drag. The pure math below is unit-tested; the loop's DOM glue is verified live.

export type Axis = 'x' | 'y' | 'xy'

export interface Params {
  edge: number // px band from a container edge where scroll engages
  speed: number // px/second at the true edge
  ramp: number // proximity exponent (2 = quadratic)
  dampenMs: number // time-dampening window from drag start
}

export interface Intent {
  up: boolean
  down: boolean
  left: boolean
  right: boolean
}

/** Does an element scroll in `axis`? Pure predicate over computed overflow + measured dims. */
export function scrollableInAxis(
  overflowX: string,
  overflowY: string,
  dims: { scrollWidth: number; clientWidth: number; scrollHeight: number; clientHeight: number },
  axis: Axis
): boolean {
  const y = (overflowY === 'auto' || overflowY === 'scroll') && dims.scrollHeight > dims.clientHeight
  const x = (overflowX === 'auto' || overflowX === 'scroll') && dims.scrollWidth > dims.clientWidth
  if (axis === 'y') return y
  if (axis === 'x') return x
  return x || y
}

/** Nearest ancestor of `el` that scrolls IN THE NEEDED AXIS (default both), or null. Axis-aware so a
 *  vertical drag skips an x-only ancestor (e.g. the table's `overflow-x` shell) to reach the real y-scroller. */
export function findScroller(el: HTMLElement | null, axis: Axis = 'xy'): HTMLElement | null {
  let n = el?.parentElement ?? null
  while (n) {
    const s = getComputedStyle(n)
    if (scrollableInAxis(s.overflowX, s.overflowY, n, axis)) return n
    n = n.parentElement
  }
  return null
}

/** Desired scroll velocity (px/sec, signed) for one axis: negative toward `lo`, positive toward `hi`,
 *  0 outside the edge band. A point past the edge (depth > edge) reads as max ramp — no viewport clamp
 *  needed. Pre-dampening, pre-limit. */
export function edgeVelocity(lo: number, hi: number, p: number, { edge, speed, ramp }: Params): number {
  const ramped = (depth: number): number => speed * Math.min(1, depth / edge) ** ramp
  if (p < lo + edge) return -ramped(lo + edge - p)
  if (p > hi - edge) return ramped(p - (hi - edge))
  return 0
}

/** Time-dampening factor 0→1 over the first `dampenMs` of a drag. */
export function dampen(elapsedMs: number, dampenMs: number): number {
  return dampenMs <= 0 ? 1 : Math.min(1, elapsedMs / dampenMs)
}

/** Zero a velocity that would push past a scroll limit — no render churn while pinned at a maxed edge. */
export function clampToLimit(v: number, pos: number, max: number): number {
  if (v < 0 && pos <= 0) return 0
  if (v > 0 && pos >= max) return 0
  return v
}

/** Sub-pixel step: fold the fractional remainder forward so slow ramps don't round to 0. Returns the
 *  integer pixels to scroll this frame and the carried remainder. */
export function stepPixels(v: number, dtMs: number, frac: number): { px: number; frac: number } {
  const raw = v * (dtMs / 1000) + frac
  const px = Math.trunc(raw)
  return { px, frac: raw - px }
}

/** Direction-intent gate. A direction may scroll only after the pointer has been OUTSIDE that
 *  direction's edge band at least once since drag start — so grabbing an item already pinned at the
 *  bottom edge doesn't immediately rocket the container. Being outside a band (velocity not pushing
 *  that way) arms it. Mutates + reads `intent`. */
export function gateIntent(intent: Intent, vx: number, vy: number): { vx: number; vy: number } {
  if (vy >= 0) intent.up = true
  if (vy <= 0) intent.down = true
  if (vx >= 0) intent.left = true
  if (vx <= 0) intent.right = true
  return {
    vx: (vx < 0 && !intent.left) || (vx > 0 && !intent.right) ? 0 : vx,
    vy: (vy < 0 && !intent.up) || (vy > 0 && !intent.down) ? 0 : vy
  }
}
```

- [ ] **Step 3: Write the failing helper tests**

Create `src/renderer/src/design-system/interactions/autoscroll.test.ts`:

```ts
import { describe, expect, it } from 'vitest'
import { clampToLimit, dampen, edgeVelocity, gateIntent, scrollableInAxis, stepPixels, type Intent, type Params } from './autoscroll'

const P: Params = { edge: 48, speed: 840, ramp: 2, dampenMs: 300 }

describe('edgeVelocity — proximity ramp', () => {
  it('is 0 away from any edge', () => {
    expect(edgeVelocity(0, 300, 150, P)).toBe(0)
  })
  it('is positive nearing the high edge, negative nearing the low edge', () => {
    expect(edgeVelocity(0, 300, 295, P)).toBeGreaterThan(0)
    expect(edgeVelocity(0, 300, 5, P)).toBeLessThan(0)
  })
  it('ramps up as the point gets closer to the edge', () => {
    const near = Math.abs(edgeVelocity(0, 300, 299, P)) // 1px from edge
    const far = Math.abs(edgeVelocity(0, 300, 260, P)) // ~40px in
    expect(near).toBeGreaterThan(far)
  })
  it('caps at full speed past the edge (no viewport clamp needed)', () => {
    expect(edgeVelocity(0, 300, 400, P)).toBe(P.speed) // 100px past the high edge → max
  })
})

describe('dampen — time ramp from drag start', () => {
  it('is 0 at t=0 and 1 after the window', () => {
    expect(dampen(0, 300)).toBe(0)
    expect(dampen(300, 300)).toBe(1)
    expect(dampen(600, 300)).toBe(1)
  })
  it('is 1 when the window is 0', () => {
    expect(dampen(0, 0)).toBe(1)
  })
})

describe('clampToLimit — no churn at a maxed edge', () => {
  it('zeroes upward scroll at the top', () => {
    expect(clampToLimit(-5, 0, 800)).toBe(0)
  })
  it('zeroes downward scroll at the bottom', () => {
    expect(clampToLimit(5, 800, 800)).toBe(0)
  })
  it('passes velocity through in the middle', () => {
    expect(clampToLimit(5, 400, 800)).toBe(5)
  })
})

describe('stepPixels — sub-pixel accumulation', () => {
  it('carries the fractional remainder so a slow ramp eventually scrolls', () => {
    const a = stepPixels(30, 16, 0) // 30px/s * 0.016s = 0.48px → 0px, 0.48 carried
    expect(a.px).toBe(0)
    const b = stepPixels(30, 16, a.frac) // 0.48 + 0.48 = 0.96 → 0px, 0.96 carried
    expect(b.px).toBe(0)
    const c = stepPixels(30, 16, b.frac) // 0.96 + 0.48 = 1.44 → 1px scrolls
    expect(c.px).toBe(1)
  })
})

describe('gateIntent — direction-intent', () => {
  it('blocks a direction until the pointer has left that band once', () => {
    const intent: Intent = { up: false, down: false, left: false, right: false }
    // Grab pinned at the bottom edge: downward velocity, down not yet armed → blocked.
    expect(gateIntent(intent, 0, 10).vy).toBe(0)
    // Pointer moves up out of the band (vy <= 0 arms down) …
    gateIntent(intent, 0, -10)
    // … now a downward push is allowed.
    expect(gateIntent(intent, 0, 10).vy).toBe(10)
  })
})

describe('scrollableInAxis', () => {
  const over = { scrollWidth: 1000, clientWidth: 200, scrollHeight: 1000, clientHeight: 200 }
  it('detects a y-scroller and rejects it for the x axis', () => {
    expect(scrollableInAxis('hidden', 'auto', over, 'y')).toBe(true)
    expect(scrollableInAxis('hidden', 'auto', over, 'x')).toBe(false)
  })
  it('detects an x-only scroller only for x / xy', () => {
    expect(scrollableInAxis('auto', 'hidden', over, 'x')).toBe(true)
    expect(scrollableInAxis('auto', 'hidden', over, 'y')).toBe(false)
    expect(scrollableInAxis('auto', 'hidden', over, 'xy')).toBe(true)
  })
  it('requires actual overflow, not just an overflow style', () => {
    const noOverflow = { scrollWidth: 200, clientWidth: 200, scrollHeight: 200, clientHeight: 200 }
    expect(scrollableInAxis('auto', 'auto', noOverflow, 'xy')).toBe(false)
  })
})
```

- [ ] **Step 4: Remove the relocated block from `engine.test.ts`**

In `src/renderer/src/design-system/interactions/engine.test.ts`: delete the `import { autoScroll } from './autoscroll'` line (line 3) and the ENTIRE `describe('autoScroll — edge ramp + limit awareness', () => { … })` block — it spans **lines 42-97** (95 is the final `expect`, 96 closes the last `it`, 97 closes the `describe`). Delete the whole block including both closing `})`; verify no orphaned `})` remains before the next `describe`. Its coverage is now carried by `autoscroll.test.ts` (Step 3) against the pure API. Leave every other test in the file untouched.

- [ ] **Step 5: Register the token file**

In `src/renderer/src/main.tsx`, add the import immediately after the token-bridge import (`import './design-system/tokens'`, line 6):

```ts
import './design-system/tokens'
import './design-system/interactions/autoscroll.css'
import './design-system/scroll-edge-fade.css'
```

- [ ] **Step 6: Run the tests — verify green**

Run: `cd Pommora && npx vitest run src/renderer/src/design-system/interactions/autoscroll.test.ts src/renderer/src/design-system/interactions/engine.test.ts`
Expected: PASS. `autoscroll.test.ts` all green; `engine.test.ts` still green with its autoscroll block gone.

- [ ] **Step 7: Typecheck**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck`
Expected: no errors. (This will surface any lingering `autoScroll`/`findScroller`-old-signature callers — Task 1 leaves the inline consumers broken because the old `autoScroll` export is gone. Expected failures: `engine.tsx`, `SurfaceView.tsx`, `paneDnd.tsx` reference the removed `autoScroll`, and `engine.tsx`/`SurfaceView.tsx`/`paneDnd.tsx` pass a 1-arg `findScroller`. That is intended — Tasks 2-5 migrate them. To keep this task independently green, do NOT commit until Step 8's note is satisfied.)

> **NOTE — task ordering:** removing the old `autoScroll` export breaks three live callers at the type level, so Task 1 alone cannot land a green typecheck. Fold Tasks 1-5 into ONE reviewable commit sequence (helpers → loop → three migrations) OR, to keep Task 1 independently green, TEMPORARILY keep a thin back-compat shim:
>
> ```ts
> /** @deprecated back-compat shim during the auto-scroll migration; removed in the block-drag task. */
> export function autoScroll(scroller: HTMLElement, x: number, y: number): boolean {
>   const r = scroller.getBoundingClientRect()
>   const p: Params = { edge: 48, speed: 14, ramp: 2, dampenMs: 0 }
>   let sx = clampToLimit(edgeVelocity(r.left, r.right, x, p), scroller.scrollLeft, scroller.scrollWidth - scroller.clientWidth)
>   let sy = clampToLimit(edgeVelocity(r.top, r.bottom, y, p), scroller.scrollTop, scroller.scrollHeight - scroller.clientHeight)
>   if (!sx && !sy) return false
>   scroller.scrollBy(sx, sy)
>   return true
> }
> ```
>
> The shim reproduces the OLD px/frame behavior (speed 14, no dampen) so the three inline callers compile and behave identically until their own task migrates them. Delete the shim in Task 6 (the last migration). **Recommended: use the shim** — it keeps every task independently green and reviewable, which is the point of the task boundaries.

- [ ] **Step 8: Commit**

```bash
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora"
git add Pommora/src/renderer/src/design-system/interactions/autoscroll.ts Pommora/src/renderer/src/design-system/interactions/autoscroll.css Pommora/src/renderer/src/design-system/interactions/autoscroll.test.ts Pommora/src/renderer/src/design-system/interactions/engine.test.ts Pommora/src/renderer/src/main.tsx
git commit -m "feat(autoscroll): tokens + pure velocity/ramp/dampen/intent helpers, axis-aware findScroller"
```

---

## Task 2: The singleton loop

The rAF loop that owns the scroll — the piece that has never run in the app (its only prior home, the engine's `Zone`, is live but its loop was the thing being replaced). Tested against a fake scroller with stubbed rAF for the lifecycle guarantees.

**Files:**
- Modify: `src/renderer/src/design-system/interactions/autoscroll.ts` (append the loop)
- Modify: `src/renderer/src/design-system/interactions/autoscroll.test.ts` (add lifecycle tests)

**Interfaces:**
- Consumes: `Axis`, `Params`, `Intent`, `edgeVelocity`, `dampen`, `clampToLimit`, `stepPixels`, `gateIntent`, `findScroller` (Task 1).
- Produces: `interface StartCfg { getPoint: () => { x: number; y: number }; scroller?: HTMLElement | null; dragEl?: HTMLElement | null; axis?: Axis; onScrolled?: () => void }`; `startAutoScroll(cfg: StartCfg): void`; `stopAutoScroll(): void`.

- [ ] **Step 1: Write the failing lifecycle tests**

Append to `src/renderer/src/design-system/interactions/autoscroll.test.ts`:

```ts
import { afterEach, beforeEach, vi } from 'vitest'
import { startAutoScroll, stopAutoScroll } from './autoscroll'

describe('startAutoScroll / stopAutoScroll — loop lifecycle', () => {
  let rafCbs: Array<(ts: number) => void>
  let rafId: number

  const fakeScroller = (): { el: HTMLElement; scrolls: () => number } => {
    let top = 400
    const el = {
      getBoundingClientRect: () => ({ top: 0, bottom: 300, left: 0, right: 300, width: 300, height: 300 }),
      get scrollTop() {
        return top
      },
      set scrollTop(v: number) {
        top = v
      },
      scrollLeft: 0,
      scrollHeight: 1000,
      clientHeight: 300,
      scrollWidth: 300,
      clientWidth: 300,
      scrollBy: (_x: number, y: number) => {
        top += y
      }
    } as unknown as HTMLElement
    return { el, scrolls: () => top }
  }

  const flush = (times: number, stepMs = 16): void => {
    let t = 0
    for (let i = 0; i < times; i++) {
      const cbs = rafCbs
      rafCbs = []
      t += stepMs
      for (const cb of cbs) cb(t)
    }
  }

  beforeEach(() => {
    rafCbs = []
    rafId = 0
    vi.stubGlobal('requestAnimationFrame', (cb: (ts: number) => void) => {
      rafCbs.push(cb)
      return ++rafId
    })
    vi.stubGlobal('cancelAnimationFrame', () => {})
  })
  afterEach(() => {
    stopAutoScroll()
    vi.unstubAllGlobals()
  })

  it('scrolls the fixed scroller toward the edge the point holds near', () => {
    const { el, scrolls } = fakeScroller()
    // Point at y=299 (1px from the bottom edge of a 0..300 rect) → downward.
    // dampenMs default read off documentElement in jsdom = fallback 300; direction-intent needs the
    // pointer to have been out of the bottom band once, so start ABOVE the band, then move in.
    let y = 150
    startAutoScroll({ getPoint: () => ({ x: 150, y }), scroller: el, dragEl: document.documentElement, axis: 'y' })
    flush(3) // arms intent (out of band), warms dampen
    const before = scrolls()
    y = 299
    flush(40) // hold at the bottom edge past the dampen window
    expect(scrolls()).toBeGreaterThan(before)
    expect(el).toBeTruthy()
  })

  it('stopAutoScroll halts the loop — no further scrolling', () => {
    const { el, scrolls } = fakeScroller()
    startAutoScroll({ getPoint: () => ({ x: 150, y: 299 }), scroller: el, dragEl: document.documentElement, axis: 'y' })
    flush(30)
    stopAutoScroll()
    const settled = scrolls()
    flush(30)
    expect(scrolls()).toBe(settled)
  })

  it('a blur event stops the loop (backstop against a leaked rAF)', () => {
    const { el, scrolls } = fakeScroller()
    startAutoScroll({ getPoint: () => ({ x: 150, y: 299 }), scroller: el, dragEl: document.documentElement, axis: 'y' })
    flush(30)
    window.dispatchEvent(new Event('blur'))
    const settled = scrolls()
    flush(30)
    expect(scrolls()).toBe(settled)
  })

  it('a second start replaces the first (singleton — one drag at a time)', () => {
    const a = fakeScroller()
    const b = fakeScroller()
    startAutoScroll({ getPoint: () => ({ x: 150, y: 299 }), scroller: a.el, dragEl: document.documentElement, axis: 'y' })
    flush(10)
    startAutoScroll({ getPoint: () => ({ x: 150, y: 299 }), scroller: b.el, dragEl: document.documentElement, axis: 'y' })
    const aAfterReplace = a.scrolls()
    flush(40)
    expect(a.scrolls()).toBe(aAfterReplace) // the first scroller is abandoned
    expect(b.scrolls()).toBeGreaterThan(400) // the second is now driven
  })

  it('fires onScrolled after a frame that actually scrolled', () => {
    const { el } = fakeScroller()
    const onScrolled = vi.fn()
    startAutoScroll({ getPoint: () => ({ x: 150, y: 299 }), scroller: el, dragEl: document.documentElement, axis: 'y', onScrolled })
    flush(40)
    expect(onScrolled).toHaveBeenCalled()
  })
})
```

- [ ] **Step 2: Run the tests — verify they FAIL**

Run: `cd Pommora && npx vitest run src/renderer/src/design-system/interactions/autoscroll.test.ts`
Expected: FAIL — `startAutoScroll`/`stopAutoScroll` are not exported yet.

- [ ] **Step 3: Append the loop to `autoscroll.ts`**

Add to the END of `src/renderer/src/design-system/interactions/autoscroll.ts`:

```ts
// ---- the singleton loop --------------------------------------------------
// One drag at a time (pointer capture guarantees it). The loop scrolls every frame off the last
// recorded point — so holding still at the edge keeps scrolling — and self-owns a termination
// backstop (blur/visibilitychange/pointercancel → stop) so a focus-steal can't strand it running.
// It stops the LOOP only; each surface still aborts its OWN gesture on its own up/cancel/blur.

interface StartCfg {
  getPoint: () => { x: number; y: number }
  scroller?: HTMLElement | null
  dragEl?: HTMLElement | null
  axis?: Axis
  onScrolled?: () => void
}

interface Live {
  raf: number
  getPoint: () => { x: number; y: number }
  scroller: HTMLElement
  axis: Axis
  params: Params
  onScrolled?: () => void
  t0: number | null
  last: number | null
  frac: { x: number; y: number }
  intent: Intent
  teardown: () => void
}

let live: Live | null = null

function readParams(el: HTMLElement): Params {
  const s = getComputedStyle(el)
  const num = (name: string, fallback: number): number => {
    const v = parseFloat(s.getPropertyValue(name))
    return Number.isFinite(v) ? v : fallback
  }
  return {
    edge: num('--autoscroll-edge', 48),
    speed: num('--autoscroll-speed', 840),
    ramp: num('--autoscroll-ramp', 2),
    dampenMs: num('--autoscroll-dampen-ms', 300)
  }
}

export type { StartCfg }

/** Begin auto-scrolling a fixed container. Resolves the scroller ONCE (explicit, else axis-aware
 *  `findScroller(dragEl, axis)`); reads tuning off `dragEl` once; then drives a singleton rAF loop. */
export function startAutoScroll(cfg: StartCfg): void {
  stopAutoScroll() // singleton: replace any running loop
  const axis = cfg.axis ?? 'xy'
  const scroller = cfg.scroller ?? findScroller(cfg.dragEl ?? null, axis)
  if (!scroller) return // no scrollable container — the drag still works, just no auto-scroll
  const onBackstop = (): void => stopAutoScroll()
  window.addEventListener('blur', onBackstop)
  document.addEventListener('visibilitychange', onBackstop)
  window.addEventListener('pointercancel', onBackstop)
  live = {
    raf: 0,
    getPoint: cfg.getPoint,
    scroller,
    axis,
    params: readParams(cfg.dragEl ?? scroller),
    onScrolled: cfg.onScrolled,
    t0: null,
    last: null,
    frac: { x: 0, y: 0 },
    intent: { up: false, down: false, left: false, right: false },
    teardown: () => {
      window.removeEventListener('blur', onBackstop)
      document.removeEventListener('visibilitychange', onBackstop)
      window.removeEventListener('pointercancel', onBackstop)
    }
  }
  live.raf = requestAnimationFrame(tick)
}

/** Stop the auto-scroll loop (and only the loop — the surface owns its gesture's own teardown). */
export function stopAutoScroll(): void {
  if (!live) return
  if (live.raf) cancelAnimationFrame(live.raf)
  live.teardown()
  live = null
}

function tick(ts: number): void {
  const L = live
  if (!L) return
  if (L.t0 === null) L.t0 = ts
  const dt = L.last === null ? 0 : ts - L.last
  L.last = ts
  const pt = L.getPoint()
  const r = L.scroller.getBoundingClientRect()
  let vx = L.axis === 'y' ? 0 : edgeVelocity(r.left, r.right, pt.x, L.params)
  let vy = L.axis === 'x' ? 0 : edgeVelocity(r.top, r.bottom, pt.y, L.params)
  ;({ vx, vy } = gateIntent(L.intent, vx, vy))
  const damp = dampen(ts - L.t0, L.params.dampenMs)
  vx = clampToLimit(vx * damp, L.scroller.scrollLeft, L.scroller.scrollWidth - L.scroller.clientWidth)
  vy = clampToLimit(vy * damp, L.scroller.scrollTop, L.scroller.scrollHeight - L.scroller.clientHeight)
  const sx = stepPixels(vx, dt, L.frac.x)
  const sy = stepPixels(vy, dt, L.frac.y)
  L.frac.x = sx.frac
  L.frac.y = sy.frac
  if (sx.px || sy.px) {
    L.scroller.scrollBy(sx.px, sy.px)
    L.onScrolled?.()
  }
  L.raf = requestAnimationFrame(tick)
}
```

If the Task-1 back-compat `autoScroll` shim is present, leave it — it's deleted in Task 6.

- [ ] **Step 4: Run the tests — verify green**

Run: `cd Pommora && npx vitest run src/renderer/src/design-system/interactions/autoscroll.test.ts`
Expected: PASS — all helper + lifecycle tests green.

- [ ] **Step 5: Typecheck**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck`
Expected: no NEW errors from `autoscroll.ts`. (If the shim was used in Task 1, the file is fully green. If not, the three inline callers still error until Tasks 3-5 — proceed as one commit sequence.)

- [ ] **Step 6: Commit**

```bash
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora"
git add Pommora/src/renderer/src/design-system/interactions/autoscroll.ts Pommora/src/renderer/src/design-system/interactions/autoscroll.test.ts
git commit -m "feat(autoscroll): singleton rAF loop + start/stop + termination backstop"
```

---

## Task 3: Migrate the drag engine onto the module

The `Zone` engine (`engine.tsx`) currently runs its OWN rAF loop (`tick`) that calls the old `autoScroll` and re-tracks. Replace that with the module: `startAutoScroll` at activation, `stopAutoScroll` at detach, and a scroll listener that re-runs `track` (the module fires `onScrolled` after each scrolled frame). This is the reference migration — it's the loop the module was extracted from.

**Files:**
- Modify: `src/renderer/src/design-system/interactions/engine.tsx`

**Interfaces:**
- Consumes: `startAutoScroll`, `stopAutoScroll`, `findScroller(el, axis)` (Tasks 1-2).

- [ ] **Step 1: Swap the import**

In `src/renderer/src/design-system/interactions/engine.tsx`, line 13, replace:

```ts
import { autoScroll, findScroller } from './autoscroll'
```
with:
```ts
import { findScroller, startAutoScroll, stopAutoScroll } from './autoscroll'
```

- [ ] **Step 2: Delete the internal loop, drive the module at activation**

In `engine.tsx`, delete the `tick` function (lines 196-201):

```ts
  const tick = (): void => {
    const d = drag.current
    if (!d.active) return
    if (d.scroller && autoScroll(d.scroller, d.lastX, d.lastY)) track(d.lastX, d.lastY)
    d.raf = requestAnimationFrame(tick)
  }
```

In `onMove`'s activation block (lines 218-226), the scroller is resolved and the loop kicked. Replace:

```ts
      d.scroller = findScroller(d.el)
      d.scroll0X = d.scroller?.scrollLeft ?? 0
      d.scroll0Y = d.scroller?.scrollTop ?? 0
      setActiveId(d.id)
      setRects(measured)
      setOverIndex(activeIdx)
      setDropState('dragging')
      notifyRef.current.onDragStart?.({ activeId: d.id })
      d.raf = requestAnimationFrame(tick)
```
with:
```ts
      d.scroller = findScroller(d.el, 'xy')
      d.scroll0X = d.scroller?.scrollLeft ?? 0
      d.scroll0Y = d.scroller?.scrollTop ?? 0
      setActiveId(d.id)
      setRects(measured)
      setOverIndex(activeIdx)
      setDropState('dragging')
      notifyRef.current.onDragStart?.({ activeId: d.id })
      // The module owns the scroll loop; on each scrolled frame it re-runs `track` off the last point,
      // exactly as the old inline `tick` did. The engine folds the scroller's delta into `track`'s
      // collision math (see `comp`), so it passes the SAME scroller explicitly.
      if (d.scroller) {
        startAutoScroll({
          getPoint: () => ({ x: drag.current.lastX, y: drag.current.lastY }),
          scroller: d.scroller,
          dragEl: d.el,
          axis: 'xy',
          onScrolled: () => track(drag.current.lastX, drag.current.lastY)
        })
      }
```

- [ ] **Step 3: Stop the loop on detach**

In `detach` (lines 234-255), the rAF cleanup (`if (d.raf) { cancelAnimationFrame(d.raf); d.raf = 0 }`) no longer governs auto-scroll — replace that guard's body's intent by adding a `stopAutoScroll()` call at the top of `detach`. Change the opening of `detach`:

```ts
  const detach = (): void => {
    const d = drag.current
    if (d.raf) {
      cancelAnimationFrame(d.raf)
      d.raf = 0
    }
```
to:
```ts
  const detach = (): void => {
    stopAutoScroll()
    const d = drag.current
    if (d.raf) {
      cancelAnimationFrame(d.raf)
      d.raf = 0
    }
```

Leave the `d.raf` field and its cleanup in place — it's now vestigial (nothing sets it) but harmless; removing the field ripples through the `drag.current` initializer in two places (`begin` and `liftKeyboard`). Keeping it is the smaller, safer diff. (A follow-up simplify pass may drop it.)

- [ ] **Step 4: Typecheck**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck`
Expected: `engine.tsx` clean.

- [ ] **Step 5: Run the interaction suite**

Run: `cd Pommora && npx vitest run src/renderer/src/design-system/interactions/`
Expected: PASS — `engine.test.ts` and `autoscroll.test.ts` green.

- [ ] **Step 6: Live-verify the engine drag**

Launch the dev app: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run dev`. Find a `Zone`-driven surface (a standalone sortable list/grid). Drag an item toward a scroll-container edge and HOLD without moving — the container must keep scrolling (the whole point of the loop-owns-scroll model). Confirm the drop insertion tracks correctly as content scrolls, and that dropping/cancelling stops the scroll cleanly. Confirm grabbing an item already at the bottom edge does NOT immediately rocket (direction-intent).

- [ ] **Step 7: Commit**

```bash
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora"
git add Pommora/src/renderer/src/design-system/interactions/engine.tsx
git commit -m "refactor(autoscroll): drive the drag engine off the shared loop"
```

---

## Task 4: Migrate SurfacePM block drag

`SurfaceView.tsx` calls the old `autoScroll` inline per-move and folds the scroller's delta into its own pointer math (`dsx`/`dsy`). Migrate to the module (explicit scroller — it self-compensates), add a `lastPoint` ref, factor the move body into a `resolve(clientX, clientY)` reused by an `onScrolled` re-resolve so a held-still drag keeps updating its drop target as content scrolls.

**Files:**
- Modify: `src/renderer/src/SurfacePM/SurfaceView.tsx`

**Interfaces:**
- Consumes: `startAutoScroll`, `stopAutoScroll`, `findScroller(el, axis)`.

- [ ] **Step 1: Swap the import**

In `src/renderer/src/SurfacePM/SurfaceView.tsx`, line 2, replace:

```ts
import { autoScroll, findScroller } from '@renderer/design-system/interactions/autoscroll'
```
with:
```ts
import { findScroller, startAutoScroll, stopAutoScroll } from '@renderer/design-system/interactions/autoscroll'
```

- [ ] **Step 2: Factor the move body + drive the module**

In the pointer-drag block (lines 423-458), the current shape resolves the scroller, then `startPointerDrag` with an `onMove` that calls inline `autoScroll` and an `onEnd`. Replace lines 423-458:

```ts
    const scroller = findScroller(host)
    const scroll0 = { x: scroller?.scrollLeft ?? 0, y: scroller?.scrollTop ?? 0 }
    let latest: SurfaceLayout = origin
    let target: DropTarget = null
    let moved = false

    startPointerDrag(e, {
      onMove: (_dx, _dy, ev) => {
        moved = true
        if (scroller) autoScroll(scroller, ev.clientX, ev.clientY)
        const dsx = (scroller?.scrollLeft ?? 0) - scroll0.x
        const dsy = (scroller?.scrollTop ?? 0) - scroll0.y
        const px = ev.clientX - downBox.left + dsx
        const py = ev.clientY - downBox.top + dsy
        setTileDrag({ id, lift: { x: px - grab.x, y: py - grab.y, w: rect.w, h: rect.h } })
        target = hitTest(g, origin, id, px, py, zone, target)
        latest = applyTarget(origin, id, target)
        setDraft(latest === origin ? null : latest)
      },
      onEnd: (commitDrag) => {
```
with:
```ts
    const scroller = findScroller(host, 'xy')
    const scroll0 = { x: scroller?.scrollLeft ?? 0, y: scroller?.scrollTop ?? 0 }
    let latest: SurfaceLayout = origin
    let target: DropTarget = null
    let moved = false
    const lastPoint = { x: e.clientX, y: e.clientY }

    // Resolve the drop target from a viewport point + the scroller's live delta. Called on every
    // pointer move AND on every auto-scrolled frame (via onScrolled) so a held-still drag near an
    // edge keeps re-targeting as content flows past.
    const resolve = (clientX: number, clientY: number): void => {
      const dsx = (scroller?.scrollLeft ?? 0) - scroll0.x
      const dsy = (scroller?.scrollTop ?? 0) - scroll0.y
      const px = clientX - downBox.left + dsx
      const py = clientY - downBox.top + dsy
      setTileDrag({ id, lift: { x: px - grab.x, y: py - grab.y, w: rect.w, h: rect.h } })
      target = hitTest(g, origin, id, px, py, zone, target)
      latest = applyTarget(origin, id, target)
      setDraft(latest === origin ? null : latest)
    }
    if (scroller) {
      startAutoScroll({
        getPoint: () => lastPoint,
        scroller,
        dragEl: host,
        axis: 'xy',
        onScrolled: () => resolve(lastPoint.x, lastPoint.y)
      })
    }

    startPointerDrag(e, {
      onMove: (_dx, _dy, ev) => {
        moved = true
        lastPoint.x = ev.clientX
        lastPoint.y = ev.clientY
        resolve(ev.clientX, ev.clientY)
      },
      onEnd: (commitDrag) => {
        stopAutoScroll()
```

Note the added `stopAutoScroll()` as the FIRST line of `onEnd` (before the existing `const decided = …`). Keep the rest of `onEnd` unchanged.

- [ ] **Step 3: Typecheck**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck`
Expected: `SurfaceView.tsx` clean.

- [ ] **Step 4: Live-verify a SurfacePM tile drag**

In the dev app, open a page/homepage with a SurfacePM block surface tall enough to scroll (the surface host doesn't scroll itself — `.detail-scroll` does). Drag a tile toward the top/bottom edge and hold — `.detail-scroll` must scroll and the tile's drop target must track as content moves. Confirm the lifted tile stays glued to the pointer (scroll compensation intact) and that release stops the scroll.

- [ ] **Step 5: Commit**

```bash
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora"
git add Pommora/src/renderer/src/SurfacePM/SurfaceView.tsx
git commit -m "refactor(autoscroll): drive SurfacePM tile drag off the shared loop"
```

---

## Task 5: Migrate the settings-pane reorder

`paneDnd.tsx` calls the old `autoScroll` inline per-move (line 181) and re-measures its snapshot on scroll via `markSnapshotDirty` (dirty-only — it re-resolves on the NEXT move). Migrate to the module and upgrade the re-measure to a re-resolve so a held-still drag keeps updating.

**Files:**
- Modify: `src/renderer/src/Components/Detail/paneDnd.tsx`

**Interfaces:**
- Consumes: `startAutoScroll`, `stopAutoScroll`, `findScroller(el, axis)`.

- [ ] **Step 1: Swap the import**

In `src/renderer/src/Components/Detail/paneDnd.tsx`, line 15, replace:

```ts
import { autoScroll, findScroller } from '@renderer/design-system/interactions/autoscroll'
```
with:
```ts
import { findScroller, startAutoScroll, stopAutoScroll } from '@renderer/design-system/interactions/autoscroll'
```

- [ ] **Step 2: Add a lastPoint ref**

Alongside the other refs (near line 71, next to `const scroller = useRef<HTMLElement | null>(null)`), add:

```ts
  const lastPoint = useRef({ x: 0, y: 0 })
```

- [ ] **Step 3: Factor the move body into `resolve`, drive the module**

The current `onMove` (lines 166-197) resolves the scroller at activation, calls inline `autoScroll`, then re-snapshots + resolves the slot + sets drag state. Restructure so the slot-resolution is a named function reused by `onScrolled`.

Replace the activation block inside `onMove` (lines 169-180):

```ts
    if (g.kind === 'pending') {
      if (Math.hypot(e.clientX - g.startX, e.clientY - g.startY) < ACTIVATION) return
      try {
        g.el.setPointerCapture(g.pid)
      } catch {
        // capture unavailable
      }
      gesture.current = { ...g, kind: 'active' }
      ghostLabel.current = labelForRef.current(g.id)
      scroller.current = findScroller(box.current)
      window.addEventListener('scroll', markSnapshotDirty, { capture: true, passive: true })
    }
    if (scroller.current) autoScroll(scroller.current, e.clientX, e.clientY)
```
with:
```ts
    if (g.kind === 'pending') {
      if (Math.hypot(e.clientX - g.startX, e.clientY - g.startY) < ACTIVATION) return
      try {
        g.el.setPointerCapture(g.pid)
      } catch {
        // capture unavailable
      }
      gesture.current = { ...g, kind: 'active' }
      ghostLabel.current = labelForRef.current(g.id)
      scroller.current = findScroller(box.current, 'y')
      window.addEventListener('scroll', markSnapshotDirty, { capture: true, passive: true })
      if (scroller.current) {
        startAutoScroll({
          getPoint: () => lastPoint.current,
          scroller: scroller.current,
          dragEl: box.current,
          axis: 'y',
          onScrolled: () => resolveSlot(g.id, lastPoint.current.y)
        })
      }
    }
    lastPoint.current = { x: e.clientX, y: e.clientY }
```

Then replace the remainder of `onMove` (lines 182-197, from `if (snapshotDirty.current …` through the `setDrag({ … })`) with a call to a new `resolveSlot` and define that function. Change:

```ts
    if (snapshotDirty.current || !snapshot.current) {
      snapshot.current = takeSnapshot()
      snapshotDirty.current = false
    }
    const snap = snapshot.current
    if (!snap) return
    const liveSlot = slot(snap.rows, snap.byId, snap.regions, e.clientY, g.id)
    live.current = liveSlot
    setDrag({
      id: g.id,
      ghostX: e.clientX + 12,
      ghostY: e.clientY + 8,
      slot: liveSlot,
      lineTop: liveSlot?.lineY != null ? liveSlot.lineY - snap.boxTop : 0
    })
  }
```
to:
```ts
    resolveSlot(g.id, e.clientY)
  }

  // Snapshot (lazily, when scroll dirtied it) then hit-test the pane at a Y. Shared by pointer move
  // and the auto-scroll re-resolve so a held-still drag near an edge keeps updating as content scrolls.
  function resolveSlot(id: string, clientY: number): void {
    if (snapshotDirty.current || !snapshot.current) {
      snapshot.current = takeSnapshot()
      snapshotDirty.current = false
    }
    const snap = snapshot.current
    if (!snap) return
    const liveSlot = slot(snap.rows, snap.byId, snap.regions, clientY, id)
    live.current = liveSlot
    setDrag({
      id,
      ghostX: lastPoint.current.x + 12,
      ghostY: clientY + 8,
      slot: liveSlot,
      lineTop: liveSlot?.lineY != null ? liveSlot.lineY - snap.boxTop : 0
    })
  }
```

- [ ] **Step 4: Stop the loop on teardown**

In `detach` (lines 127-140), add `stopAutoScroll()` as the first line (after `const g = gesture.current` guard is fine, but simplest at the very top):

```ts
  const detach = (): void => {
    stopAutoScroll()
    const g = gesture.current
    if (g.kind === 'idle') return
```

- [ ] **Step 5: Typecheck + tests**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck && npx vitest run src/renderer/src/Components/Detail/paneDndModel.test.ts`
Expected: clean typecheck; the model test (pure hit-test logic) stays green (untouched).

- [ ] **Step 6: Live-verify the property-reorder pane**

In the dev app, open a collection's Properties settings pane (the reorderable property list) with enough properties to scroll. Drag a property row to the top/bottom edge and hold — the pane scrolls, the insertion line tracks. Confirm release stops the scroll and Escape mid-drag still cancels cleanly (its capture-phase Escape handler is untouched).

- [ ] **Step 7: Commit**

```bash
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora"
git add Pommora/src/renderer/src/Components/Detail/paneDnd.tsx
git commit -m "refactor(autoscroll): drive settings-pane reorder off the shared loop"
```

---

## Task 6: Delete the block-drag duplicate loop

`blockDrag.ts` has an entirely separate auto-scroll: its own `EDGE`/`edgeStep`/`tick`/`g.raf`, scrolling CM6's `view.scrollDOM`, re-measuring drop candidates on the scroll event. Replace it with the module (explicit CM scroller, axis `'y'`, `onScrolled` → its existing `remeasure`). Also delete the Task-1 back-compat `autoScroll` shim if it was added.

**Files:**
- Modify: `src/renderer/src/MarkdownPM/editor/blockDrag.ts`
- Modify: `src/renderer/src/design-system/interactions/autoscroll.ts` (delete the shim, if present)

**Interfaces:**
- Consumes: `startAutoScroll`, `stopAutoScroll`.

- [ ] **Step 1: Add the import**

At the top of `src/renderer/src/MarkdownPM/editor/blockDrag.ts`, add to the imports:

```ts
import { startAutoScroll, stopAutoScroll } from '../../design-system/interactions/autoscroll'
```

- [ ] **Step 2: Delete the local auto-scroll machinery**

Remove the `EDGE` constant and `edgeStep` (lines 54-57):

```ts
// Auto-scroll tuning: the band at the scroller's top/bottom edge where a held drag keeps scrolling, and the
// per-frame step (ramped by how deep into the band the pointer is, capped).
const EDGE = 48
const edgeStep = (depth: number): number => Math.min(Math.ceil((depth / EDGE) * 14), 14)
```

Remove the `tick` function (lines 103-117):

```ts
  // Auto-scroll while the pointer sits in the top/bottom EDGE band, so a block can reach a target that was
  // off-screen at grab time (CM only renders ~viewport, so far targets aren't candidates until scrolled in).
  const tick = (): void => {
    g.raf = 0
    if (!g.active) return
    const r = host.getBoundingClientRect()
    let dy = 0
    if (g.lastY < r.top + EDGE) dy = -edgeStep(r.top + EDGE - g.lastY)
    else if (g.lastY > r.bottom - EDGE) dy = edgeStep(g.lastY - (r.bottom - EDGE))
    if (dy === 0) return
    const before = host.scrollTop
    host.scrollTop += dy
    if (host.scrollTop === before) return // at the scroll limit — wait for the pointer to move again
    g.raf = requestAnimationFrame(tick) // the scrollTop write fires `scroll` → onScroll → remeasure (one path)
  }
```

In `onMove`'s activation block, start the module and remove the rAF kick. Replace lines 119-136:

```ts
  const onMove = (ev: PointerEvent): void => {
    if (!g.active) {
      if (Math.hypot(ev.clientX - e.clientX, ev.clientY - e.clientY) < ACTIVATION) return
      g.active = true
      document.body.style.cursor = 'grabbing'
      try {
        host.setPointerCapture(e.pointerId)
      } catch {
        // capture unavailable
      }
      onDragStart?.(view, block) // e.g. unfold a heading section before it moves — folds can't survive the move
      view.dispatch({ effects: setShade.of({ from: block.from, to: block.to }) })
      g.cands = collectCands(view, block)
    }
    g.lastY = ev.clientY
    repick()
    if (!g.raf) g.raf = requestAnimationFrame(tick) // (re)start auto-scroll if we're near an edge
  }
```
with:
```ts
  const onMove = (ev: PointerEvent): void => {
    if (!g.active) {
      if (Math.hypot(ev.clientX - e.clientX, ev.clientY - e.clientY) < ACTIVATION) return
      g.active = true
      document.body.style.cursor = 'grabbing'
      try {
        host.setPointerCapture(e.pointerId)
      } catch {
        // capture unavailable
      }
      onDragStart?.(view, block) // e.g. unfold a heading section before it moves — folds can't survive the move
      view.dispatch({ effects: setShade.of({ from: block.from, to: block.to }) })
      g.cands = collectCands(view, block)
      // The shared loop scrolls CM's viewport (explicit scroller — findScroller can't derive scrollDOM).
      // No `onScrolled` needed: the loop's `scrollBy` fires CM's native `scroll` → the existing `onScroll`
      // → `remeasure`, so far candidates (CM only renders ~viewport) become targetable as they scroll in —
      // the exact single path the old local `tick` relied on.
      startAutoScroll({ getPoint: () => ({ x: 0, y: g.lastY }), scroller: host, dragEl: host, axis: 'y' })
    }
    g.lastY = ev.clientY
    repick()
  }
```

- [ ] **Step 3: Drop the `g.raf` field and stop the loop in `finish`**

In `g`'s initializer (line 88), remove the `raf: 0` field:

```ts
  const g = { active: false, done: false, overlay: new Overlay(), cands: [] as Cand[], slot: null as Cand | null, lastY: e.clientY }
```

In `finish` (lines 145-171), replace the rAF cancel with `stopAutoScroll()`. Change:

```ts
    g.done = true
    document.body.style.cursor = ''
    if (g.raf) cancelAnimationFrame(g.raf)
    host.removeEventListener('pointermove', onMove)
```
to:
```ts
    g.done = true
    document.body.style.cursor = ''
    stopAutoScroll()
    host.removeEventListener('pointermove', onMove)
```

The existing `host.addEventListener('scroll', onScroll, …)` and `onScroll → remeasure` stay — this ONE path now covers BOTH wheel scroll AND the loop's auto-scroll (the module's `scrollBy` fires the same native `scroll` event), which is exactly why Task 6 Step 2 passes no `onScrolled` — a second re-measure path would double-walk `collectCands` every frame (the "never expensive on every X" rule). The `window.blur → onCancel` handler stays (it aborts the GESTURE; the module's own blur backstop independently stops the loop — belt and suspenders, both correct).

- [ ] **Step 4: Delete the back-compat shim (if added in Task 1)**

If Task 1 added the `@deprecated` `autoScroll` shim to `autoscroll.ts`, delete it now — this was its last caller.

- [ ] **Step 5: Typecheck**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck`
Expected: clean — no remaining references to the old `autoScroll` anywhere.

- [ ] **Step 6: Live-verify the editor block drag**

In the dev app, open a long page (taller than the editor viewport). Grab a block's gutter handle and drag toward the top/bottom edge, holding still — the editor (`.cm-scroller`) scrolls, and the fixed insertion line keeps snapping to real block boundaries as off-screen blocks scroll in (proving `onScrolled → remeasure`). Confirm Escape and window-blur both abort cleanly with no lingering scroll.

- [ ] **Step 7: Commit**

```bash
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora"
git add Pommora/src/renderer/src/MarkdownPM/editor/blockDrag.ts Pommora/src/renderer/src/design-system/interactions/autoscroll.ts
git commit -m "refactor(autoscroll): delete block-drag's duplicate loop, drive the shared one"
```

---

## Task 7: Retrofit the sidebar drag

`sidebarDnd.tsx` has NO auto-scroll today. It measures rows once at activation and dirties its snapshot on scroll (`markSnapshotDirty`), re-resolving on the next move. Add the module (scroller = `.sidebar` via `findScroller(el, 'y')`), a `lastPoint` ref, and an `onScrolled` that re-resolves the slot so a held-still drag keeps updating.

**Files:**
- Modify: `src/renderer/src/Sidebar/sidebarDnd.tsx`

**Interfaces:**
- Consumes: `startAutoScroll`, `stopAutoScroll`, `findScroller(el, axis)`.

- [ ] **Step 1: Read the file's move/detach/begin shape**

Read `src/renderer/src/Sidebar/sidebarDnd.tsx` lines 220-300 to anchor the exact `onMove` activation block, the slot-resolution call, `detach` (near line 237), and where the `scroll` listener is added (line 290). The retrofit mirrors Task 5's structure: factor the slot resolution into a function, feed `lastPoint`, start/stop the module.

- [ ] **Step 2: Add the import + a lastPoint ref**

Add `startAutoScroll`, `stopAutoScroll`, and `findScroller` to the existing import from the interactions module (or add a new import line if none exists):

```ts
import { findScroller, startAutoScroll, stopAutoScroll } from '@renderer/design-system/interactions/autoscroll'
```

Add a ref alongside the others:

```ts
  const lastPoint = useRef({ x: 0, y: 0 })
```

- [ ] **Step 3: Factor slot-resolution + drive the module at activation**

In `onMove`, at the activation transition (where `gesture.current` flips to `active` and the `scroll` listener is added, ~line 289-290), resolve the scroller and start the module. The scroller is `.sidebar` — `findScroller(g.el, 'y')`. After activation, feed `lastPoint.current` and call the factored resolver.

Add inside the activation block, right after the existing `window.addEventListener('scroll', markSnapshotDirty, …)`:

```ts
      const sc = findScroller(g.el, 'y')
      if (sc) {
        startAutoScroll({
          getPoint: () => lastPoint.current,
          scroller: sc,
          dragEl: g.el,
          axis: 'y',
          onScrolled: () => resolveSlot(lastPoint.current.y)
        })
      }
```

(Use the gesture's element reference for `g.el` — match the file's actual field name; it is the dragged row element.)

Update `lastPoint.current` at the top of every move (after the activation guard). The sidebar's actual post-activation body is `computeTarget(e.clientY)` + `setDrag(...)` — and `computeTarget` (lines ~116-127) already owns the lazy snapshot dirty-check + re-measure internally, so there is NO inline `slot()`/`takeSnapshot` to factor out. Just wrap `computeTarget(clientY)` + `setDrag(...)` in a `resolveSlot(clientY)` that both `onMovePtr` and the module's `onScrolled` call. Reading `lastPoint.current` (not the live event) is what lets `onScrolled` re-resolve while the pointer holds still.

- [ ] **Step 4: Stop the loop on teardown**

Add `stopAutoScroll()` as the first line of `detach` (~line 237):

```ts
  const detach = (): void => {
    stopAutoScroll()
    const g = gesture.current
    …
```

- [ ] **Step 5: Typecheck + model test**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck && npx vitest run src/renderer/src/Sidebar/sidebarDndModel.test.ts src/renderer/src/Sidebar/sidebarDnd.test.tsx`
Expected: clean typecheck; both sidebar drag tests stay green (they test the model + component, not auto-scroll).

- [ ] **Step 6: Live-verify the sidebar drag**

In the dev app, make the sidebar tree tall enough to scroll. Drag a sidebar item toward the top/bottom edge and hold — `.sidebar` scrolls, the insertion line + ghost track. Confirm drop/cancel stops the scroll and the drag-ghost portal is unaffected.

- [ ] **Step 7: Commit**

```bash
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora"
git add Pommora/src/renderer/src/Sidebar/sidebarDnd.tsx
git commit -m "feat(autoscroll): retrofit the sidebar drag onto the shared loop"
```

---

## Task 8: Retrofit the table row drag

`tableDnd.tsx` has NO auto-scroll today but ALREADY has the scroll re-measure path (`onDragScroll` → re-snapshot). This is the B-2 fix: the correct scroller is `.detail-scroll` (y), NOT the x-only `.table-view` — so `findScroller(el, 'y')` is mandatory (a plain either-axis `findScroller` would grab `.table-view` whenever columns overflow and never scroll vertically).

**Files:**
- Modify: `src/renderer/src/Detail/Views/Table/tableDnd.tsx`

**Interfaces:**
- Consumes: `startAutoScroll`, `stopAutoScroll`, `findScroller(el, axis)`.

- [ ] **Step 1: Read the move/scroll/detach shape**

Read `src/renderer/src/Detail/Views/Table/tableDnd.tsx` lines 55-200 to anchor: the `snapshot`/`onDragScroll` refs (55-57), `takeSnapshot`, the slot hit-test in `onMove`, the `onScroll` handler added at activation (line 184-185), and `detach` (129-146).

- [ ] **Step 2: Add the import + a lastPoint ref**

```ts
import { findScroller, startAutoScroll, stopAutoScroll } from '@renderer/design-system/interactions/autoscroll'
```
```ts
  const lastPoint = useRef({ x: 0, y: 0 })
```

- [ ] **Step 3: Factor slot-resolution + drive the module**

Factor the `onMove` post-activation logic (re-snapshot-if-dirty → `slot(...)` → `setDrag(...)`) into a `resolveSlot(clientY)` function called by both `onMove` and the module's `onScrolled`. The file already defines `onScroll` (which re-snapshots) added at activation — extend the activation block to start the module with the y-scroller:

At activation (~line 180-185, where `onDragScroll.current = onScroll` and the `scroll` listener is registered), add:

```ts
      const sc = findScroller(g.el, 'y') // '.detail-scroll' — deliberately skips the x-only '.table-view'
      if (sc) {
        startAutoScroll({
          getPoint: () => lastPoint.current,
          scroller: sc,
          dragEl: g.el,
          axis: 'y',
          onScrolled: () => resolveSlot(lastPoint.current.y)
        })
      }
```

Update `lastPoint.current` each move. Leave the existing `onScroll` re-snapshot as-is (do NOT also make it call `resolveSlot`) — the module's `scrollBy` fires the same native `scroll`, so `onScroll` runs anyway; adding a `resolveSlot` there on top of `onScrolled` would resolve twice per auto-scrolled frame (F3). The single re-resolve driver during auto-scroll is `onScrolled`; wheel-scroll during a drag keeps its pre-existing "re-snapshot now, re-resolve on next move" behavior. Ensure `resolveSlot` re-snapshots first (mirror the existing dirty/`takeSnapshot` gate).

- [ ] **Step 4: Stop the loop on teardown**

Add `stopAutoScroll()` as the first line of `detach`.

- [ ] **Step 5: Typecheck + tests**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck && npx vitest run src/renderer/src/Detail/Views/Table/tableDnd.test.tsx`
Expected: clean typecheck; table row drag test green.

- [ ] **Step 6: Live-verify — including the B-2 fix**

In the dev app, open a table view with MORE rows than fit AND enough columns to make `.table-view` horizontally overflow (so the wrong-scroller bug would trigger). Drag a row to the bottom edge and hold — the table's vertical scroller (`.detail-scroll`) MUST scroll (not the horizontal `.table-view`). Confirm the drop line tracks rows as they scroll in. This is the exact scenario the axis-aware `findScroller` fixes.

- [ ] **Step 7: Commit**

```bash
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora"
git add Pommora/src/renderer/src/Detail/Views/Table/tableDnd.tsx
git commit -m "feat(autoscroll): retrofit table row drag (axis-y scroller — fixes the x-only .table-view trap)"
```

---

## Task 9: Retrofit the table band drag

`bandDnd.tsx` (group-header reorder) mirrors `tableDnd`'s structure: frozen snapshot, `markSnapshotDirty` on scroll (dirty-only), no auto-scroll. Same retrofit, same y-scroller (`.detail-scroll`).

**Files:**
- Modify: `src/renderer/src/Detail/Views/Table/bandDnd.tsx`

**Interfaces:**
- Consumes: `startAutoScroll`, `stopAutoScroll`, `findScroller(el, axis)`.

- [ ] **Step 1: Read the move/scroll/detach shape**

Read `src/renderer/src/Detail/Views/Table/bandDnd.tsx` lines 74-180 to anchor `takeSnapshot`, `markSnapshotDirty`, the `onMove` activation + slot logic (149-177), the `scroll` listener (line 157), and `detach` (110-125).

- [ ] **Step 2: Add the import + a lastPoint ref**

```ts
import { findScroller, startAutoScroll, stopAutoScroll } from '@renderer/design-system/interactions/autoscroll'
```
```ts
  const lastPoint = useRef({ x: 0, y: 0 })
```

- [ ] **Step 3: Factor slot-resolution + drive the module**

Factor the post-activation slot logic into `resolveSlot(clientY)` (re-snapshot-if-dirty → band hit-test → `setDrag`). At activation (right after the existing `window.addEventListener('scroll', markSnapshotDirty, …)`, ~line 157), start the module:

```ts
      const sc = findScroller(g.el, 'y')
      if (sc) {
        startAutoScroll({
          getPoint: () => lastPoint.current,
          scroller: sc,
          dragEl: g.el,
          axis: 'y',
          onScrolled: () => resolveSlot(lastPoint.current.y)
        })
      }
```

Update `lastPoint.current` each move and route both move + `onScrolled` through `resolveSlot`.

- [ ] **Step 4: Stop the loop on teardown**

Add `stopAutoScroll()` as the first line of `detach`.

- [ ] **Step 5: Typecheck + tests**

Run: `cd Pommora && env -u ELECTRON_RUN_AS_NODE npm run typecheck && npx vitest run src/renderer/src/Detail/Views/Table/bandDnd.test.tsx`
Expected: clean typecheck; band drag test green.

- [ ] **Step 6: Live-verify the band drag**

In the dev app, open a grouped table with more group bands than fit. Drag a group header toward the bottom edge and hold — `.detail-scroll` scrolls and the band insertion line tracks. Confirm a mid-drag collapse/expand (which dirties the snapshot) still re-resolves correctly under auto-scroll.

- [ ] **Step 7: Commit**

```bash
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora"
git add Pommora/src/renderer/src/Detail/Views/Table/bandDnd.tsx
git commit -m "feat(autoscroll): retrofit table band drag onto the shared loop"
```

---

## Task 10: Full gate + doc reconciliation

The whole feature is green per-surface; now run the complete gate and reconcile the docs that just went false. Per the decision log's G-1/G-2/G-3.

**Files:**
- Modify: `.claude/Features/PommoraDND.md`
- Modify: `.claude/Features/Interaction.md`
- Modify: `.claude/History.md`
- Modify: `Pommora/src/renderer/src/SurfacePM/README.md` (line 70 names the deleted `autoScroll`)

- [ ] **Step 1: Full test + typecheck + build gate**

Run:
```bash
cd Pommora && set -o pipefail
env -u ELECTRON_RUN_AS_NODE npm run typecheck
npx vitest run
env -u ELECTRON_RUN_AS_NODE npm run build
```
Expected: typecheck clean (two `tsc` passes), full suite green, build succeeds. Read the vitest SUMMARY line — do not trust a piped exit code.

- [ ] **Step 2: Reconcile `PommoraDND.md`**

The "Auto-scroll (`autoscroll.ts`)" bullet (line 57) describes the OLD single-engine, nearest-ancestor, not-tokenized model. Rewrite it to describe the shared app-wide module: a singleton rAF loop that scrolls a FIXED scroller resolved once at drag start (explicit or axis-aware `findScroller`), fed by every drag surface, time-dampened + direction-gated + frame-rate-independent + sub-pixel + limit-aware, tuned by `autoscroll.css` tokens, with a self-owned termination backstop. Name the consumers (engine, SurfacePM, settings pane, block-drag, sidebar, table rows, table bands) and note the Prospects (list drag, column-horizontal, GFM-table, grouping pane, the cross-list board). Keep it durable-fact only — name the tokens and the treatment, NOT the literal values.

- [ ] **Step 3: Reconcile `Interaction.md`**

- Line 61 (§"Drag Motion", the engine brief): the "quadratic edge-proximity auto-scroll ramp (`interactions/autoscroll.ts`, rAF)" and the SEPARATE "edge auto-scroll (`editor/blockDrag.ts`)" now describe ONE shared engine. Restate as a single primitive; delete the block-drag-has-its-own-auto-scroll claim (its loop is gone — it now drives the shared one).
- Line 83 (§"Duration Inventory"): the `interactions/autoscroll.ts:5-6` `EDGE = 48`/`MAX = 14` "keep local" entry is false — those constants are deleted and the values are now the `--autoscroll-edge` / `--autoscroll-speed` tokens. Update the entry to name the token set (`autoscroll.css`) instead of the removed literals.
- Line 101 (§"Not motion"): the `interactions/autoscroll.ts:1` comment reference is stale (line moved). Either drop the line reference (docs name, code holds exacts) or update it to point at the file, not a line.

- [ ] **Step 4: Add the `History.md` decision entry**

Add a concise entry recording the decision: one app-wide auto-scroll module replacing two duplicated per-surface loops, extracted from the engine's proven ramp math with a NEW loop-owns-the-scroll lifecycle; the fixed-scroller-at-start model (chosen over per-frame `elementsFromPoint` because no core Pommora drag crosses scroll containers); axis-aware `findScroller`; token-driven via `autoscroll.css`; core surfaces wired (engine · SurfacePM · settings pane · block-drag · sidebar · table rows · table bands), the block-drag duplicate deleted; Prospects deferred (list drag needs the re-measure path, the cross-list board needs per-frame resolution reintroduced). Follow `History.md`'s existing entry convention.

- [ ] **Step 5: Fix the SurfacePM README vocabulary line**

In `Pommora/src/renderer/src/SurfacePM/README.md`, line 70 lists `findScroller`/`autoScroll` as the shared interaction vocabulary. `autoScroll` is deleted (Task 6) — replace it with `startAutoScroll`/`stopAutoScroll` (the vocabulary is now the shared loop). Keep `findScroller` (it survives, axis-aware).

- [ ] **Step 6: Commit**

```bash
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora"
git add .claude/Features/PommoraDND.md .claude/Features/Interaction.md .claude/History.md Pommora/src/renderer/src/SurfacePM/README.md
git commit -m "docs(autoscroll): reconcile PommoraDND + Interaction + History + SurfacePM README for the shared loop"
```

---

## Prospects (explicitly NOT in this plan)

Deferred per the decision log — each named with its real cost, not "feed the point later":

- **MarkdownPM list drag** (`editor/listDrag.ts`) — measures drop candidates ONCE at activation in viewport coords with NO scroll listener. Auto-scrolling it would strand the insertion line on stale gaps. It needs `blockDrag`'s scroll→re-measure path built first — its own scoped task.
- **Table column-reorder** (horizontal, `TableView.tsx startColumnDrag`) — the horizontal counterpart; wire with axis `'x'` against `.table-view` once desired.
- **MarkdownPM GFM-table drag** (`Tables/TableView.tsx`).
- **Grouping pane** (`groupingDnd.tsx`).
- **The cross-list board** (`group.tsx`) — architecturally distinct: its per-move `zoneAt` crosses scroll containers, so it ALONE needs the rejected per-frame "scroller under the pointer" resolution reintroduced. NOT a fixed-scroller retrofit; do not scope it as a simple one.
- **Per-surface override VALUES** — the seam ships (tokens read off the drag element, overridable on any ancestor); tune a surface's `--autoscroll-*` only when one proves it needs it.
- **Non-DOM scroll target** — a registry `scroll(dx,dy)` callback for a future canvas that pans its own viewport. Not needed now.

---

## Self-Review

**Spec coverage** (decision log → task):
- Standalone module, singleton rAF loop, `start/stop`, fixed scroller resolved once, token params cached, px/sec × dt, sub-pixel, dampening, direction-intent → Tasks 1-2. ✓
- Axis-aware `findScroller(el, axis)` (B-2) → Task 1 (helper) + Task 8 (the table application that proves it). ✓
- Loop-only termination backstop, not gesture abort (H3 / round-2 finding 2) → Task 2 (module backstop) + every migration keeps its own gesture abort (blockDrag's `blur → finish` kept in Task 6). ✓
- Tokens off the DRAG ELEMENT, not the scroller (C-2 / round-2 finding 1) → `readParams(cfg.dragEl ?? scroller)` in Task 2; every consumer passes `dragEl`. ✓
- Explicit scroller for self-compensating + CM drags (B-3a) → engine (Task 3), SurfacePM (Task 4), block-drag (Task 6) pass explicit scrollers; `findScroller` path for sidebar/table/band (Tasks 7-9). ✓
- Loop owns scroll, surfaces feed the point + re-resolve on scroll (E-1) → `onScrolled` re-resolve in every consumer; the held-still-at-edge re-resolve is called out explicitly (the gap that dirty-only surfaces had). ✓
- Delete the block-drag duplicate, migrate the 3 existing consumers, NO second copy remains (Core) → Tasks 3-6. ✓
- Tokens in `autoscroll.css`, registered after the token bridge (C-1) → Task 1. ✓
- Doc reconciliation G-1/G-2/G-3 → Task 10. ✓
- Prospects parked, not built → listed, zero tasks. ✓

**One gap surfaced during grounding, folded in:** the decision log framed each core surface's scroll re-measure as "unchanged / existing" (B-3), but grounding showed `paneDnd`/`sidebar`/`band`/`table` only DIRTY on scroll and re-resolve on the NEXT move — which leaves a held-still drag's insertion line stale while auto-scrolling. The plan upgrades each to re-resolve via `onScrolled` (Tasks 5, 7, 8, 9). `blockDrag` already re-resolved (its `onScroll → remeasure`), so it's unchanged there.

**Placeholder scan:** no TBDs; every code step shows real code or a precise edit against a read anchor. Retrofit Tasks 7-9 begin with a "read the file" step because the exact field names (`g.el` vs the gesture's element ref) must be confirmed live rather than guessed — the surrounding structure and the exact insertion points are given.

**Type consistency:** `startAutoScroll(cfg: StartCfg)` / `stopAutoScroll()` / `findScroller(el, axis)` names and signatures are identical across Tasks 2-9. `Params`/`Intent`/`Axis` are defined once in Task 1 and only consumed after. `edgeVelocity`/`dampen`/`clampToLimit`/`stepPixels`/`gateIntent` signatures match between their definition (Task 1) and the loop's use (Task 2).
