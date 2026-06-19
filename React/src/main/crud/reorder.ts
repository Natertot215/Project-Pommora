// Order persistence. The renderer computes a new order (drag/drop) and sends the full
// id list; main just persists it — top-level orders to .nexus/state.json, within-
// container orders to the container's sidecar. Read-modify-write so a reorder doesn't
// clobber other state keys.

import { mkdir } from 'node:fs/promises'
import { join } from 'node:path'
import type { z } from 'zod'
import { mutateJson, pathExists } from '../io/atomicWrite'
import { nexusDir, nexusConfig, NEXUS_CONFIG_FILES, SIDECAR_FILENAME, type SidecarKind } from '../paths'
import { updateFolderSidecar } from './folderEntity'
import { pageTypeSidecar, pageCollectionSidecar, pageSetSidecar } from '@shared/schemas'
import { ok, type Result } from '@shared/result'
import type { StateOrderKey, ChildOrderKey } from '@shared/mutate'

// `StateOrderKey` (vaults + tiers) is the shared IPC type. The within-container keys add
// `page_order` (written on a page move, never a reorderChildren) onto the shared child keys.
export type { StateOrderKey }
export type ContainerOrderKey = ChildOrderKey | 'page_order'

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

// The container folder kinds, detected by which sidecar exists on disk — so an order
// (page_order on any; collection_order on a vault; set_order on a collection) persists with
// one call regardless of the parent's kind.
const CONTAINER_SIDECARS = [
  { kind: 'pageType' as const, schema: pageTypeSidecar },
  { kind: 'collection' as const, schema: pageCollectionSidecar },
  { kind: 'set' as const, schema: pageSetSidecar }
]

/** Persist a within-folder order (`page_order` / `collection_order` / `set_order`), resolving
 *  the folder's kind from its sidecar on disk. A raw/adopted folder with no recognized sidecar
 *  is a no-op (order falls back to title). */
export async function setChildOrder(absFolder: string, key: ContainerOrderKey, ids: string[]): Promise<Result<null>> {
  for (const { kind, schema } of CONTAINER_SIDECARS) {
    if (await pathExists(join(absFolder, SIDECAR_FILENAME[kind]))) {
      const r = await setContainerOrder(absFolder, kind, schema, key, ids)
      if (!r.ok) return r
      return ok(null)
    }
  }
  return ok(null)
}
