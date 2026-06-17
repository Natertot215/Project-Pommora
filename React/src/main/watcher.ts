// Phase 4 — live filesystem watcher. The watcher ONLY reads: on a debounced
// settle it re-reads the tree and pushes it to the renderer over 'nexus:changed'.
// No pause flag — an in-app write that echoes back is a harmless redundant
// re-read (a read-only watcher can't loop; re-rendering an identical tree is a
// no-op). ⌘R Reload stays as the manual fallback.

import { relative, sep } from 'node:path'
import chokidar, { type FSWatcher } from 'chokidar'
import type { BrowserWindow } from 'electron'
import { readNexus } from './readNexus'
import { sessionRoot } from './session'

const SETTLE_MS = 200

let watcher: FSWatcher | null = null
let debounce: ReturnType<typeof setTimeout> | null = null

// Ignore the config / index / trash internals + dotfiles — they aren't part of
// the tree the renderer shows and they churn on every mutation. Checks only the
// path BELOW the root, so a dot-segment in the root's own absolute path (e.g. a
// nexus under ~/.something) can't blank the whole watch.
export function ignoredUnder(root: string): (path: string) => boolean {
  return (path) => {
    const rel = relative(root, path)
    if (!rel || rel.startsWith('..')) return false // the root itself / outside root
    return rel.split(sep).some((seg) => seg === '.nexus' || seg === '.trash' || seg.startsWith('.'))
  }
}

/** Start (or restart) watching `root`, pushing fresh trees to `win`. */
export function startWatcher(root: string, win: BrowserWindow): void {
  stopWatcher() // one watcher at a time — replace any prior session's
  watcher = chokidar.watch(root, {
    ignored: ignoredUnder(root),
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
