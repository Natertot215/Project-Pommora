// Assignment ops — a Collection's sidecar `properties` is a flat array of registry prop-ids
// (which nexus-wide defs this Collection validates). References, not definitions: assign runs
// no name-clash check, unassign never touches the def or any page value (reversible by design).

import { join } from 'node:path'
import { readSidecar, writeSidecar } from '../sidecarIO'
import { pageCollectionSidecar } from '@shared/schemas'
import { readNexus } from '../readNexus'
import type { CollectionNode, SetNode } from '@shared/types'
import { ok, fail, type Result } from '@shared/result'

async function read(folder: string): Promise<{ sidecar: Record<string, unknown>; ids: string[] } | null> {
  const sidecar = await readSidecar(folder, 'collection', pageCollectionSidecar)
  if (sidecar === null) return null
  return { sidecar: sidecar as Record<string, unknown>, ids: (sidecar.properties as string[] | undefined) ?? [] }
}

const write = async (folder: string, sidecar: Record<string, unknown>, ids: string[]): Promise<void> =>
  writeSidecar(folder, 'collection', { ...sidecar, properties: ids })

export async function assignProperty(collectionFolder: string, propertyId: string): Promise<Result<null>> {
  const r = await read(collectionFolder)
  if (!r) return fail('not-found', 'Collection not found.')
  if (r.ids.includes(propertyId)) return ok(null)
  await write(collectionFolder, r.sidecar, [...r.ids, propertyId])
  return ok(null)
}

export async function unassignProperty(collectionFolder: string, propertyId: string): Promise<Result<null>> {
  const r = await read(collectionFolder)
  if (!r) return fail('not-found', 'Collection not found.')
  await write(collectionFolder, r.sidecar, r.ids.filter((id) => id !== propertyId))
  return ok(null)
}

/** Absolute folder paths of every Collection whose sidecar assigns propertyId — the reverse
 *  lookup that scopes a global op's fan-out. Reads raw sidecar ids (not the tree's resolved
 *  defs) so a dangling assignment still counts as an assigner to clean up. */
export async function assigners(root: string, propertyId: string): Promise<string[]> {
  const tree = await readNexus(root)
  const out: string[] = []
  const visit = async (node: CollectionNode | SetNode): Promise<void> => {
    if (node.kind === 'collection') {
      const r = await read(join(root, node.path))
      if (r?.ids.includes(propertyId)) out.push(join(root, node.path))
    }
    for (const s of node.sets ?? []) await visit(s)
  }
  const all = [...(tree.collections ?? []), ...tree.userSections.flatMap((s) => s.collections ?? [])]
  for (const c of all) await visit(c)
  return out
}

export async function reorderAssignment(collectionFolder: string, propertyId: string, toIndex: number): Promise<Result<null>> {
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
