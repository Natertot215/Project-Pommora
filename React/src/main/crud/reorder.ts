// Order persistence. The renderer computes a new order (drag/drop) and sends the full
// id list; main just persists it — top-level orders to .nexus/state.json, within-
// container orders to the container's sidecar. Read-modify-write so a reorder doesn't
// clobber other state keys.

import { mkdir } from 'node:fs/promises'
import type { z } from 'zod'
import { mutateJson } from '../io/atomicWrite'
import { nexusDir, nexusConfig, NEXUS_CONFIG_FILES, type SidecarKind } from '../paths'
import { updateFolderSidecar } from './folderEntity'
import { ok, type Result } from '@shared/result'

export type StateOrderKey = 'vault_order' | 'area_order' | 'topic_order' | 'project_order'
export type ContainerOrderKey = 'collection_order' | 'set_order' | 'page_order'

/** Persist a top-level order (vaults or a context tier) to .nexus/state.json. */
export async function setStateOrder(
  nexusRoot: string,
  key: StateOrderKey,
  ids: string[]
): Promise<Result<string[]>> {
  await mkdir(nexusDir(nexusRoot), { recursive: true })
  await mutateJson<Record<string, unknown>>(
    nexusConfig(nexusRoot, NEXUS_CONFIG_FILES.state),
    () => ({}),
    (state) => ({ ...state, [key]: ids })
  )
  return ok(ids)
}

/** Persist a within-container order (collections/sets/pages) to the container sidecar,
 *  preserving its other (incl. foreign) keys. */
export async function setContainerOrder<S extends z.ZodType>(
  absFolder: string,
  kind: SidecarKind,
  schema: S,
  key: ContainerOrderKey,
  ids: string[]
): Promise<Result<z.infer<S>>> {
  return updateFolderSidecar(absFolder, kind, schema, { [key]: ids } as Partial<z.infer<S>>)
}
