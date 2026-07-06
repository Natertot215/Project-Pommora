// Phase 4 — live filesystem watcher. The watcher ONLY reads: on a debounced
// settle it re-reads the tree and pushes it to the renderer over 'nexus:changed'.
// No pause flag — an in-app write that echoes back is a harmless redundant
// re-read (a read-only watcher can't loop; re-rendering an identical tree is a
// no-op). ⌘R Reload stays as the manual fallback.

import { relative, sep } from 'node:path'
import chokidar, { type FSWatcher } from 'chokidar'
import type { BrowserWindow } from 'electron'
import { asStringArray } from './coerce'
import { excludedMatcher } from './exclusion'
import { readJsonObject } from './io/atomicWrite'
import { nexusConfig, NEXUS_CONFIG_FILES } from './paths'
import { readNexus } from './readNexus'
import { sessionRoot } from './session'

const SETTLE_MS = 200

let watcher: FSWatcher | null = null
let debounce: ReturnType<typeof setTimeout> | null = null

// Ignore only what ISN'T user-meaningful tree content: the SQLite index (index.db*,
// which thrashes on every mutation via WAL), the .trash, and OS/editor dotfile cruft.
// Crucially we DO watch .nexus/ — Contexts (.nexus/<tier>/) and settings/state (accent,
// labels, ordering) live there, so external edits to them must auto-refresh. Checks only
// the path BELOW the root, so a dot-segment in the root's own absolute path (e.g. a nexus
// under ~/.something) can't blank the whole watch.
export function ignoredUnder(root: string, excluded: string[] = []): (path: string) => boolean {
  // User-excluded folders never reach the tree, so their churn must not cost a reconcile
  // (un-excluding a folder mid-session takes effect on the next nexus open / watcher restart).
  const isExcluded = excludedMatcher(excluded)
  return (path) => {
    const rel = relative(root, path)
    if (!rel || rel.startsWith('..')) return false // the root itself / outside root
    const segs = rel.split(sep)
    return (
      segs.some(
        (seg) =>
          seg === '.trash' || // deleted items — not part of the tree
          seg.startsWith('index.db') || // SQLite index + its WAL/SHM — churns on every mutation
          (seg.startsWith('.') && seg !== '.nexus') // dotfile cruft, but .nexus holds contexts + settings
      ) || isExcluded(segs)
    )
  }
}

/** Start (or restart) watching `root`, pushing fresh trees to `win`. */
export async function startWatcher(root: string, win: BrowserWindow): Promise<void> {
  stopWatcher() // one watcher at a time — replace any prior session's
  const settings = (await readJsonObject(nexusConfig(root, NEXUS_CONFIG_FILES.settings))) ?? {}
  const excluded = asStringArray(settings.excluded_folders) ?? []
  if (sessionRoot() !== root) return // session switched during the settings read
  watcher = chokidar.watch(root, {
    ignored: ignoredUnder(root, excluded),
    ignoreInitial: true, // existing files aren't "changes"
    persistent: true,
    awaitWriteFinish: { stabilityThreshold: SETTLE_MS, pollInterval: 50 },
    atomic: true // coalesce the mv-_tmp atomic writes our writers use
  })
  const onEvent = (): void => {
    if (debounce) clearTimeout(debounce)
    debounce = setTimeout(() => void push(root, win), SETTLE_MS)
  }
  watcher
    .on('add', onEvent)
    .on('change', onEvent)
    .on('unlink', onEvent)
    .on('addDir', onEvent)
    .on('unlinkDir', onEvent)
    // An unhandled 'error' on an EventEmitter is RE-THROWN → it would crash the main
    // process (EMFILE/ENOSPC from fd/inotify-watch exhaustion, EPERM, a watched dir
    // vanishing). Log + no-op; the tree stays as last-read and ⌘R Reload recovers.
    .on('error', (error: unknown) => console.error('Nexus watcher error (non-fatal):', error))
}

/** Stop watching + cancel any pending push. Safe to call when not watching. */
export function stopWatcher(): void {
  if (debounce) {
    clearTimeout(debounce)
    debounce = null
  }
  if (watcher) {
    void watcher.close()
    watcher = null
  }
}

async function push(root: string, win: BrowserWindow): Promise<void> {
  if (sessionRoot() !== root || win.isDestroyed()) return // session switched / window gone
  try {
    const tree = await readNexus(root)
    if (!win.isDestroyed()) win.webContents.send('nexus:changed', tree)
  } catch {
    // Transient FS state mid-write — the next settle re-reads (Reload is the fallback).
  }
}
