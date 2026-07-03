// Assignment ops — a Collection's sidecar `properties` is a flat array of registry prop-ids
// (which nexus-wide defs this Collection validates). References, not definitions: assign runs
// no name-clash check and restores any Remove-cache; the unassign leg lives in
// crud/removeProperty (strip + cache, C-3).

import { join } from 'node:path'
import { readSidecar, writeSidecar } from '../sidecarIO'
import { pageCollectionSidecar } from '@shared/schemas'
import { readNexus } from '../readNexus'
import { restoreCachedValues } from './removeProperty'
import { serializeSchemaOp } from './schemaChain'
import type { CollectionNode, SetNode } from '@shared/types'
import { ok, fail, type Result } from '@shared/result'

async function read(folder: string): Promise<{ sidecar: Record<string, unknown>; ids: string[] } | null> {
  const sidecar = await readSidecar(folder, 'collection', pageCollectionSidecar)
  if (sidecar === null) return null
  return { sidecar: sidecar as Record<string, unknown>, ids: (sidecar.properties as string[] | undefined) ?? [] }
}

const write = async (folder: string, sidecar: Record<string, unknown>, ids: string[]): Promise<void> =>
  writeSidecar(folder, 'collection', { ...sidecar, properties: ids })

// Unchained internals — the chained publics compose them; a chained fn awaiting another
// chained fn would deadlock the schema chain.
async function assignInner(root: string, collectionFolder: string, propertyId: string): Promise<Result<null>> {
  const r = await read(collectionFolder)
  if (!r) return fail('not-found', 'Collection not found.')
  if (r.ids.includes(propertyId)) return ok(null)
  await write(collectionFolder, r.sidecar, [...r.ids, propertyId])
  return restoreCachedValues(root, collectionFolder, propertyId)
}

async function reorderInner(collectionFolder: string, propertyId: string, toIndex: number): Promise<Result<null>> {
  const r = await read(collectionFolder)
  if (!r) return fail('not-found', 'Collection not found.')
  const from = r.ids.indexOf(propertyId)
  if (from < 0) return fail('not-found', 'Property not assigned.')
  const next = [...r.ids]
  const [moved] = next.splice(from, 1)
  next.splice(Math.min(Math.max(toIndex, 0), next.length), 0, moved)
  await write(collectionFolder, r.sidecar, next)
  return ok(null)
}

/** Assign appends the id (idempotent), then restores any Remove-cache for it (C-3) —
 *  root scopes the registry read the per-value reconciliation needs. */
export function assignProperty(root: string, collectionFolder: string, propertyId: string): Promise<Result<null>> {
  return serializeSchemaOp(() => assignInner(root, collectionFolder, propertyId))
}

/** The atomic assign-at-slot (E-2): append + restore + placement land in ONE chain slot,
 *  so no sibling op can interleave between the assign and its reorder. */
export function assignPropertyAt(
  root: string,
  collectionFolder: string,
  propertyId: string,
  toIndex?: number
): Promise<Result<null>> {
  return serializeSchemaOp(async () => {
    const a = await assignInner(root, collectionFolder, propertyId)
    if (!a.ok || toIndex === undefined) return a
    return reorderInner(collectionFolder, propertyId, toIndex)
  })
}

/** Absolute folder paths of EVERY Collection in the tree (schema-owning folders only —
 *  Sets inherit). The shared walk for global fan-outs that must reach non-assigners too:
 *  a Remove-cache lives on a sidecar that no longer assigns the id (D-6). */
export async function allCollectionFolders(root: string): Promise<string[]> {
  const tree = await readNexus(root)
  const out: string[] = []
  const visit = (node: CollectionNode | SetNode): void => {
    if (node.kind === 'collection') out.push(join(root, node.path))
    for (const s of node.sets ?? []) visit(s)
  }
  for (const c of [...(tree.collections ?? []), ...tree.userSections.flatMap((s) => s.collections ?? [])]) visit(c)
  return out
}

export function reorderAssignment(collectionFolder: string, propertyId: string, toIndex: number): Promise<Result<null>> {
  return serializeSchemaOp(() => reorderInner(collectionFolder, propertyId, toIndex))
}
