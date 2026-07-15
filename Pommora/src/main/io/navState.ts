// The Navigation layer's per-nexus persistence: two SYNCED sidecars under `.nexus/` —
// `navRecents.json` (the auto history stream, MRU, with a per-entry `pinned` float) and
// `navFavorites.json` (the durable favorites list). Unlike activeViews/folds these are NOT
// device-local — a user's recents and favorites follow them across machines (single-user,
// last-writer-wins sync model).
//
// The renderer owns the in-memory arrays and the MRU/dedupe/cap/prune logic; main is the
// persister. Recents writes DEBOUNCE (passive nav records fire on every selection), coalescing
// to one disk write; the pin toggle and the quit/switch flush write immediately. Favorites are
// deliberate user acts, so they always write immediately. The pending recents write carries its
// own root, so a late flush always lands in the nexus it was recorded for.

import { mkdir } from 'node:fs/promises'
import { isPlainObject } from '@shared/propertyValue'
import type { NavFavorite, NavState, NavTarget, RecentEntry } from '@shared/types'
import { nexusConfig, nexusDir, NEXUS_CONFIG_FILES } from '../paths'
import { readJsonArray, writeJson } from './atomicWrite'
import { serializeOnFile } from './fileLock'

const recentsPath = (root: string): string => nexusConfig(root, NEXUS_CONFIG_FILES.navRecents)
const favoritesPath = (root: string): string => nexusConfig(root, NEXUS_CONFIG_FILES.navFavorites)

/** Coalescing window for the passive nav-record write — long enough that a burst of selections
 *  (Back/Forward, rapid clicks) collapses to one write, short enough that a normal quit's flush
 *  rarely has work to do. */
const RECENTS_DEBOUNCE_MS = 500

// --- validation (lenient read) --------------------------------------------

const NAV_KINDS = new Set(['homepage', 'context', 'collection', 'set', 'page', 'task', 'event'])

/** A well-formed nav target: known kind, an `id` on every kind but homepage, and a `path` on the
 *  path-carrying kinds (set/page). Hand-edited or cross-version junk is dropped, never crashes. */
function isNavTarget(v: unknown): v is NavTarget {
  if (!isPlainObject(v)) return false
  const kind = v.kind
  if (typeof kind !== 'string' || !NAV_KINDS.has(kind)) return false
  if (kind === 'homepage') return true
  if (typeof v.id !== 'string') return false
  if (kind === 'set' || kind === 'page') return typeof v.path === 'string'
  return true
}

function isRecentEntry(v: unknown): v is RecentEntry {
  if (!isNavTarget(v)) return false
  const { pinned } = v as { pinned?: unknown }
  return pinned === undefined || typeof pinned === 'boolean'
}

// --- reads ----------------------------------------------------------------

/** Both sidecars, read leniently in parallel: absent / corrupt → empty; invalid entries dropped. */
export async function readNavState(root: string): Promise<NavState> {
  const [recentsRaw, favoritesRaw] = await Promise.all([readJsonArray(recentsPath(root)), readJsonArray(favoritesPath(root))])
  return {
    recents: recentsRaw.filter(isRecentEntry),
    favorites: favoritesRaw.filter(isNavTarget)
  }
}

// --- writes ---------------------------------------------------------------

// In-flight disk writes (immediate + flushed-debounce), so the quit gate can wait for EVERY nav
// write — not just the debounced one. Favorites and pins write immediately, so without this they'd
// be the layer's least-durable writes despite being its most deliberate.
const inFlight = new Set<Promise<unknown>>()

function writeList(path: string, root: string, entries: unknown[]): Promise<void> {
  const p = serializeOnFile(path, async () => {
    await mkdir(nexusDir(root), { recursive: true })
    await writeJson(path, entries)
  })
  inFlight.add(p)
  const clear = (): void => void inFlight.delete(p)
  p.then(clear, clear)
  return p
}

/** Favorites — immediate (a deliberate user act; loss is worse than a passive record's). */
export async function writeFavorites(root: string, entries: NavFavorite[]): Promise<void> {
  await writeList(favoritesPath(root), root, entries)
}

// --- recents debounce -----------------------------------------------------

let pending: { root: string; entries: RecentEntry[] } | null = null
let timer: ReturnType<typeof setTimeout> | null = null

function clearTimer(): void {
  if (timer) {
    clearTimeout(timer)
    timer = null
  }
}

/** Debounced recents write — the passive nav-record path. The newest payload supersedes any
 *  in-flight one, so only the last state in a burst reaches disk. */
export function scheduleRecentsWrite(root: string, entries: RecentEntry[]): void {
  pending = { root, entries }
  clearTimer()
  timer = setTimeout(() => void flushRecents().catch((e) => console.error('nav recents debounced flush failed:', e)), RECENTS_DEBOUNCE_MS)
}

/** Immediate recents write (pin toggle). Supersedes and cancels any pending debounced write so a
 *  stale payload can't land after it. */
export async function writeRecentsNow(root: string, entries: RecentEntry[]): Promise<void> {
  clearTimer()
  pending = null
  await writeList(recentsPath(root), root, entries)
}

/** Whether a debounced recents write is still queued — the quit hook checks this before deciding
 *  to defer the quit. */
export function hasPendingRecents(): boolean {
  return pending !== null
}

/** Flush any queued recents write immediately (drives the debounce → disk). Idempotent: a no-op
 *  when nothing is pending. */
export async function flushRecents(): Promise<void> {
  clearTimer()
  const p = pending
  pending = null
  if (p) await writeList(recentsPath(p.root), p.root, p.entries)
}

/** Any nav write still owed to disk — a queued debounce OR an immediate write (favorite/pin) still
 *  settling. The quit gate + nexus-switch check this before deciding to wait. */
export function hasPendingNavWrites(): boolean {
  return pending !== null || inFlight.size > 0
}

/** Drain EVERY owed nav write (before-quit + nexus switch): flush the debounce, then wait out all
 *  in-flight writes, looping so a record that lands mid-drain is caught too. */
export async function flushNavWrites(): Promise<void> {
  while (hasPendingNavWrites()) {
    await flushRecents()
    await Promise.allSettled([...inFlight])
  }
}
