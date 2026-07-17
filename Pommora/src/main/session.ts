// The currently-open nexus for this app run. One window → one nexus (v1), so the
// session is a single main-process value: the absolute root path, or null when
// nothing is open. The IPC read/write handlers resolve against sessionRoot().

import { realpath, stat } from 'node:fs/promises'
import type { AppConfig } from './appConfig'

let currentRoot: string | null = null

/** The open nexus root, or null when nothing is open. */
export function sessionRoot(): string | null {
  return currentRoot
}

/** Open a nexus at `root` (absolute path). The stored root is CANONICALIZED (realpath) so it
 *  keys the same string resolveUnderRoot hands the cell-write path: a symlinked root ancestry
 *  (e.g. macOS /var→/private/var, an external mount) would otherwise split the cascade and
 *  cell-write file locks into different buckets and they'd stop serializing (F1). Falls back to
 *  the raw path if it can't be resolved (e.g. a not-yet-existing path in a test). */
export async function openSession(root: string): Promise<void> {
  currentRoot = await realpath(root).catch(() => root)
}

/** Close the current nexus (back to empty state). */
export function closeSession(): void {
  currentRoot = null
}

/** True when `p` exists and is a directory (follows symlinks). Existence only —
 *  a genuinely unreadable dir surfaces later as a read error, handled there.
 *  Shared by launch-restore and the drag-to-open path guard. */
export async function isExistingDir(p: string): Promise<boolean> {
  try {
    return (await stat(p)).isDirectory()
  } catch {
    return false
  }
}

/**
 * Which nexus to reopen on launch: the persisted lastNexusPath, but only if it
 * still points at an existing directory — otherwise null (empty state). NEVER
 * prompts; a launch must not block on a modal (headless runs / tests must not hang).
 */
export async function resolveRestorePath(config: AppConfig): Promise<string | null> {
  if (config.lastNexusPath && (await isExistingDir(config.lastNexusPath))) {
    return config.lastNexusPath
  }
  return null
}

/** True when any path segment is a system, volume, or in-nexus trash dir (~/.Trash, /.Trashes, a
 *  nexus's .trash) — a recents entry pointing into one is a deleted nexus that shouldn't resurface. */
export function isTrashedPath(p: string): boolean {
  return p.split('/').some((seg) => {
    const s = seg.toLowerCase()
    return s === '.trash' || s === '.trashes'
  })
}

/** Filter recents to entries that still resolve to a live, non-trashed directory, order preserved —
 *  a deleted (trashed) nexus is dropped so Open Recent never lists it. */
export async function pruneRecents(recents: string[]): Promise<string[]> {
  const keep = await Promise.all(
    recents.map((p) => (isTrashedPath(p) ? Promise.resolve(false) : isExistingDir(p))),
  )
  return recents.filter((_, i) => keep[i])
}
