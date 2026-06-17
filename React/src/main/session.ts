// The currently-open nexus for this app run. One window → one nexus (v1), so the
// session is a single main-process value: the absolute root path, or null when
// nothing is open. The IPC read/write handlers resolve against sessionRoot().

import { stat } from 'node:fs/promises'
import type { AppConfig } from './appConfig'

let currentRoot: string | null = null

/** The open nexus root, or null when nothing is open. */
export function sessionRoot(): string | null {
  return currentRoot
}

/** Open a nexus at `root` (absolute path). */
export function openSession(root: string): void {
  currentRoot = root
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
