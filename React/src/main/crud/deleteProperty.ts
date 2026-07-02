// Global property delete — the one nexus-wide destructive fan-out. Snapshot-first (a
// timestamped JSON of the def + every page value lands in `.trash`, so the scrub is
// recoverable), then one atomic SchemaTransaction strips the value from every collection's
// pages, drops the id from every assignment, and purges every Remove-cache block (D-6) —
// and finally the def leaves the registry. The daily non-destructive op is Remove
// (crud/removeProperty); this is the rare one, and it saves nothing restorable in-app.

import { join } from 'node:path'
import { readFile, mkdir, writeFile } from 'node:fs/promises'
import { readRegistry, type PropertyRegistry } from '../io/propertiesRegistry'
import { removeFromRegistry } from './registryProperty'
import { allCollectionFolders } from './assignment'
import { SchemaTransaction } from '../io/schemaTransaction'
import { stripPageMember } from './schema'
import { readSidecar } from '../sidecarIO'
import { pageCollectionSidecar } from '@shared/schemas'
import { listMarkdownFiles } from '../io/walk'
import { SIDECAR_FILENAME } from '../paths'
import { serializeJson } from '../io/atomicWrite'
import { splitFrontmatter } from '../readNexus'
import { isPlainObject } from '@shared/propertyValue'
import { nowIso } from './util'
import { fail, type Result } from '@shared/result'

async function snapshot(root: string, propertyId: string, def: PropertyRegistry[string], folders: string[]): Promise<void> {
  const values: Record<string, unknown> = {}
  for (const folder of folders) {
    for (const file of await listMarkdownFiles(folder)) {
      let props: unknown
      try {
        props = splitFrontmatter(await readFile(file, 'utf8')).properties
      } catch {
        continue
      }
      if (isPlainObject(props) && propertyId in props) values[file] = props[propertyId]
    }
  }
  const trash = join(root, '.trash')
  await mkdir(trash, { recursive: true })
  const stamp = new Date().toISOString().replace(/[:.]/g, '-')
  await writeFile(
    join(trash, `${stamp}__property-${propertyId}.json`),
    serializeJson({ propertyId, def, values })
  )
}

export async function deleteProperty(root: string, propertyId: string): Promise<Result<null>> {
  const registry = await readRegistry(root)
  const def = registry.defs[propertyId]
  if (!def) return fail('not-found', 'Property not found.')

  // EVERY collection folder, not just current assigners — a Remove-cache block lives on a
  // sidecar that no longer assigns the id, and pre-cache dormant values may sit on any page (D-6).
  const folders = await allCollectionFolders(root)
  await snapshot(root, propertyId, def, folders)

  const tx = new SchemaTransaction()
  for (const folder of folders) {
    const sidecar = await readSidecar(folder, 'collection', pageCollectionSidecar)
    if (sidecar) {
      const assigned = (sidecar.properties as string[] | undefined) ?? []
      const cacheAll = isPlainObject(sidecar.property_cache) ? sidecar.property_cache : undefined
      const hadCache = cacheAll !== undefined && propertyId in cacheAll
      if (assigned.includes(propertyId) || hadCache) {
        const next: Record<string, unknown> = {
          ...sidecar,
          properties: assigned.filter((id) => id !== propertyId),
          modified_at: nowIso()
        }
        if (hadCache) {
          const cache = { ...cacheAll }
          delete cache[propertyId]
          if (Object.keys(cache).length) next.property_cache = cache
          else delete next.property_cache
        }
        tx.stage(join(folder, SIDECAR_FILENAME.collection), serializeJson(next))
      }
    }
    for (const file of await listMarkdownFiles(folder)) {
      let content: string
      try {
        content = await readFile(file, 'utf8')
      } catch {
        continue
      }
      const stripped = stripPageMember(content, propertyId)
      if (stripped !== null) tx.stage(file, stripped)
    }
  }
  await tx.commit()
  return removeFromRegistry(root, propertyId)
}
