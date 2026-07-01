// Assignment ops — a Collection's sidecar `properties` is a flat array of registry prop-ids
// (which nexus-wide defs this Collection validates). References, not definitions: assign runs
// no name-clash check, unassign never touches the def or any page value (reversible by design).

import { readSidecar, writeSidecar } from '../sidecarIO'
import { pageCollectionSidecar } from '@shared/schemas'
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
