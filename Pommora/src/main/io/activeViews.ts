// The per-machine active-view pointer: `.nexus/activeViews.json`, keyed by container id → the id of
// the view currently selected for that Collection/Set. Deliberately NOT in the synced sidecar's
// `views[]` — keeping the selection local avoids modified_at churn and cross-machine selection
// conflicts. Inside `.nexus/` it's outside the content walk + any body-sync — per-machine by
// construction. Mirrors folds.ts.
import { mkdir } from 'node:fs/promises'
import { nexusConfig, nexusDir, NEXUS_CONFIG_FILES } from '../paths'
import { readJsonObject, writeJson } from './atomicWrite'

/** container id → active view id. */
export type ActiveViews = Record<string, string>

const activeViewsPath = (root: string): string => nexusConfig(root, NEXUS_CONFIG_FILES.activeViews)

/** Lenient read: absent / corrupt → `{}`; keeps only string entries. */
export async function readActiveViews(root: string): Promise<ActiveViews> {
  const obj = await readJsonObject(activeViewsPath(root))
  if (obj === null) return {}
  const out: ActiveViews = {}
  for (const [containerId, viewId] of Object.entries(obj)) {
    if (typeof viewId === 'string') out[containerId] = viewId
  }
  return out
}

/** Set (or, with an empty viewId, clear) the active view for a container. */
export async function writeActiveViews(root: string, containerId: string, viewId: string): Promise<void> {
  const current = await readActiveViews(root)
  if (viewId === '') delete current[containerId]
  else current[containerId] = viewId
  await mkdir(nexusDir(root), { recursive: true })
  await writeJson(activeViewsPath(root), current)
}
