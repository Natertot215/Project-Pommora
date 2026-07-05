// The app's device-level config: a single JSON file in Electron's userData dir,
// owned by the main process. Holds cross-session state that is NOT nexus data —
// which nexus to reopen on launch, the recents list (later: trash mode, window
// bounds). Parametrized by the userData dir (not app.getPath) so the logic stays
// pure Node and unit-testable without booting Electron.

import { join } from 'node:path'
import { readJsonObject, writeJson } from './io/atomicWrite'

/** Where a delete sends the entity: the in-nexus `.trash` (portable, index-aware) or the
 *  macOS system Trash (Finder-recoverable). Device-level — system Trash isn't portable
 *  nexus data — so it lives in app config, not the nexus. */
export type TrashMode = 'nexus' | 'system'

/** Default delete target: the portable in-nexus trash. */
export const DEFAULT_TRASH_MODE: TrashMode = 'nexus'

export interface AppConfig {
  /** Absolute path of the last nexus opened; restored on launch if still readable. */
  lastNexusPath?: string
  /** Most-recently-opened nexus paths, newest first (deduped, capped). */
  recents?: string[]
  /** Delete target; defaults to DEFAULT_TRASH_MODE when absent/invalid. */
  trashMode?: TrashMode
}

const FILE = 'pommora.json'

/** The config file's absolute path under the given userData directory. */
export function appConfigPath(userDataDir: string): string {
  return join(userDataDir, FILE)
}

/** Read the config, tolerating a missing or malformed file (→ empty defaults). */
export async function readAppConfig(userDataDir: string): Promise<AppConfig> {
  const obj = await readJsonObject(appConfigPath(userDataDir))
  if (!obj) return {}
  return {
    lastNexusPath: typeof obj.lastNexusPath === 'string' ? obj.lastNexusPath : undefined,
    recents: Array.isArray(obj.recents)
      ? obj.recents.filter((p): p is string => typeof p === 'string')
      : undefined,
    trashMode: obj.trashMode === 'system' || obj.trashMode === 'nexus' ? obj.trashMode : undefined
  }
}

/** Write the config atomically (stable, sorted keys + trailing newline). */
export async function writeAppConfig(userDataDir: string, config: AppConfig): Promise<void> {
  await writeJson(appConfigPath(userDataDir), config)
}

/** Prepend `path` to recents, removing any prior occurrence (move-to-front) and
 *  capping the list. The one shaper of the recents list. */
export function addRecent(recents: string[], path: string, cap = 10): string[] {
  return [path, ...recents.filter((p) => p !== path)].slice(0, cap)
}
