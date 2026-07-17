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

/** Identity of a drivable target — kind+id, or bare kind for the id-less homepage (navKey's shape;
 *  duplicated here because the renderer's helper can't cross into main). */
const targetKey = (t: SelectTarget): string => ('id' in t ? `${t.kind}:${t.id}` : t.kind)

/** A well-formed persisted tab: id + target + a history of drivable targets whose index points AT the
 *  target (the lockstep invariant openTab's dedup relies on). A newtab tab always reads with an empty
 *  history; a desynced or malformed history degrades to just the target (the tab survives;
 *  Back/Forward starts fresh). This is the sanitizing gate for a synced, cross-version file — the
 *  store assumes every invariant enforced here. */
function readTab(v: unknown): Tab | null {
  if (!isPlainObject(v) || typeof v.id !== 'string' || !isTabTarget(v.target)) return null
  if (v.target.kind === 'newtab') return { id: v.id, target: v.target, navStack: [], navIndex: -1 }
  const stack = Array.isArray(v.navStack) ? v.navStack.filter(isSelectTarget) : []
  const index = typeof v.navIndex === 'number' && Number.isInteger(v.navIndex) ? v.navIndex : -1
  const sane =
    stack.length > 0 &&
    index >= 0 &&
    index < stack.length &&
    targetKey(stack[index]) === targetKey(v.target)
  if (sane) return { id: v.id, target: v.target, navStack: stack, navIndex: index }
  // Target/history desync: re-point the index at the target's entry when the stack holds one
  // (preserving the history), else degrade to a single-entry stack.
  const at = stack.findIndex((s) => targetKey(s) === targetKey(v.target as SelectTarget))
  if (at !== -1) return { id: v.id, target: v.target, navStack: stack, navIndex: at }
  return { id: v.id, target: v.target, navStack: [v.target], navIndex: 0 }
}

// --- read -------------------------------------------------------------------

/** The persisted tab set, read leniently: absent / corrupt → null (the store seeds a fresh NavView);
 *  invalid tabs dropped; a dangling activeTabId is the store's job to reconcile (it also has to fold
 *  in the derived pinned tabs this file never sees). */
export async function readTabsState(root: string): Promise<TabSet | null> {
  const raw = await readJsonObject(tabsPath(root))
  if (!raw || !Array.isArray(raw.tabs)) return null
  // Dedupe by id — closeTab drops by-id, so two tabs sharing one would close together.
  const seen = new Set<string>()
  const tabs = raw.tabs
    .map(readTab)
    .filter((t): t is Tab => t !== null && !seen.has(t.id) && (seen.add(t.id), true))
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
  timer = setTimeout(
    () => void flushTabsWrites().catch((e) => console.error('tabs debounced flush failed:', e)),
    TABS_DEBOUNCE_MS,
  )
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
