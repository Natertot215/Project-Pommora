// The tab set's per-nexus persistence: one SYNCED sidecar under `.nexus/` — `tabs.json`, the ordered
// UNPINNED tab list + the active-tab pointer + each tab's Back/Forward targets (D-8/D-8a). Pinned tabs
// are never stored here — they derive from `.nexus/pins/` (C-6; a second synced copy would re-introduce
// the whole-array-LWW desync the per-pin files dodge). Warm view-state (scroll/undo) is session-only
// and never persisted.
//
// The renderer owns the in-memory set; main is the persister. Writes DEBOUNCE (every navigation mutates
// the set), coalescing to one disk write; the quit/switch drain flushes immediately. The pending payload
// carries its own root, so a late flush always lands in the nexus it was recorded for.

import { mkdir } from 'node:fs/promises'
import { isPlainObject } from '@shared/propertyValue'
import type { SelectTarget, Tab, TabSet, TabTarget } from '@shared/types'
import { nexusConfig, nexusDir, NEXUS_CONFIG_FILES } from '../paths'
import { readJsonObject, writeJson } from './atomicWrite'
import { serializeOnFile } from './fileLock'

const tabsPath = (root: string): string => nexusConfig(root, NEXUS_CONFIG_FILES.tabs)

/** Coalescing window for the per-navigation tab-set write — same rationale as the recents debounce:
 *  a burst of navigations collapses to one write; the quit/switch drain rarely has work to do. */
const TABS_DEBOUNCE_MS = 500

// --- validation (lenient read) --------------------------------------------

const SELECT_KINDS = new Set(['homepage', 'context', 'collection', 'set', 'page'])

/** A well-formed drivable target: known kind, an `id` on every kind but homepage, and a `path` on the
 *  path-carrying kinds (set/page). Hand-edited or cross-version junk is dropped, never crashes. */
function isSelectTarget(v: unknown): v is SelectTarget {
  if (!isPlainObject(v)) return false
  const kind = v.kind
  if (typeof kind !== 'string' || !SELECT_KINDS.has(kind)) return false
  if (kind === 'homepage') return true
  if (typeof v.id !== 'string') return false
  if (kind === 'set' || kind === 'page') return typeof v.path === 'string'
  return true
}

function isTabTarget(v: unknown): v is TabTarget {
  return (isPlainObject(v) && v.kind === 'newtab') || isSelectTarget(v)
}

/** A well-formed persisted tab: id + target + a history of drivable targets with an in-range index.
 *  A malformed history degrades to just the target (the tab survives; Back/Forward starts fresh). */
function readTab(v: unknown): Tab | null {
  if (!isPlainObject(v) || typeof v.id !== 'string' || !isTabTarget(v.target)) return null
  const stack = Array.isArray(v.navStack) ? v.navStack.filter(isSelectTarget) : []
  const index = typeof v.navIndex === 'number' && Number.isInteger(v.navIndex) ? v.navIndex : -1
  const sane = stack.length > 0 && index >= 0 && index < stack.length
  if (sane) return { id: v.id, target: v.target, navStack: stack, navIndex: index }
  return v.target.kind === 'newtab'
    ? { id: v.id, target: v.target, navStack: [], navIndex: -1 }
    : { id: v.id, target: v.target, navStack: [v.target], navIndex: 0 }
}

// --- read -------------------------------------------------------------------

/** The persisted tab set, read leniently: absent / corrupt → null (the store seeds a fresh NavView);
 *  invalid tabs dropped; a dangling activeTabId is the store's job to reconcile (it also has to fold
 *  in the derived pinned tabs this file never sees). */
export async function readTabsState(root: string): Promise<TabSet | null> {
  const raw = await readJsonObject(tabsPath(root))
  if (!raw || !Array.isArray(raw.tabs)) return null
  const tabs = raw.tabs.map(readTab).filter((t): t is Tab => t !== null)
  return { tabs, activeTabId: typeof raw.activeTabId === 'string' ? raw.activeTabId : '' }
}

// --- debounced write --------------------------------------------------------

// In-flight disk writes, so the quit gate can wait for a flushed write still settling.
const inFlight = new Set<Promise<unknown>>()

let pending: { root: string; set: TabSet } | null = null
let timer: ReturnType<typeof setTimeout> | null = null

function clearTimer(): void {
  if (timer) {
    clearTimeout(timer)
    timer = null
  }
}

function writeSet(root: string, set: TabSet): Promise<void> {
  const path = tabsPath(root)
  const p = serializeOnFile(path, async () => {
    await mkdir(nexusDir(root), { recursive: true })
    await writeJson(path, set)
  })
  inFlight.add(p)
  const clear = (): void => void inFlight.delete(p)
  p.then(clear, clear)
  return p
}

/** Debounced tab-set write — the per-navigation path. The newest payload supersedes any pending one,
 *  so only the last state in a burst reaches disk. */
export function scheduleTabsWrite(root: string, set: TabSet): void {
  pending = { root, set }
  clearTimer()
  timer = setTimeout(() => void flushTabsWrites().catch((e) => console.error('tabs debounced flush failed:', e)), TABS_DEBOUNCE_MS)
}

/** Any tab write still owed to disk — a queued debounce OR a flushed write still settling. The quit
 *  gate + nexus-switch drain check this. */
export function hasPendingTabsWrites(): boolean {
  return pending !== null || inFlight.size > 0
}

/** Drain every owed tab write (before-quit + nexus switch): flush the debounce, then wait out the
 *  in-flight writes, looping so a write landing mid-drain is caught too. */
export async function flushTabsWrites(): Promise<void> {
  while (hasPendingTabsWrites()) {
    clearTimer()
    const p = pending
    pending = null
    if (p) await writeSet(p.root, p.set)
    await Promise.allSettled([...inFlight])
  }
}
