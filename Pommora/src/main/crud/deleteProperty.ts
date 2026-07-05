// Global property delete — the one nexus-wide destructive fan-out. Snapshot-first (a
// timestamped JSON of the def + every page value lands in `.trash`, so the scrub is
// recoverable), then strips the value from every collection's page under its file lock (the
// same lock the cell-write path takes), drops the id from every assignment, purges every
// Remove-cache block (D-6), and finally removes the def from the registry. Per-file, not
// cross-file atomic — the `.trash` snapshot is the recovery net, so a partial run re-runs
// cleanly. The daily non-destructive op is Remove (crud/removeProperty); this is the rare
// one, and it saves nothing restorable in-app.

import { join } from 'node:path'
import { readFile, mkdir, writeFile } from 'node:fs/promises'
import { readRegistry, type PropertyRegistry } from '../io/propertiesRegistry'
import { removeFromRegistry } from './registryProperty'
import { allCollectionFolders } from './assignment'
import { serializeSchemaOp } from './schemaChain'
import { rewritePageSerialized } from '../io/fileLock'
import { stripPageMember } from './schema'
import { readSidecar } from '../sidecarIO'
import { pageCollectionSidecar } from '@shared/schemas'
import { listMarkdownFiles } from '../io/walk'
import { SIDECAR_FILENAME } from '../paths'
import { serializeJson, writeJson } from '../io/atomicWrite'
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

export function deleteProperty(root: string, propertyId: string): Promise<Result<null>> {
  return serializeSchemaOp(() => deleteInner(root, propertyId))
}

async function deleteInner(root: string, propertyId: string): Promise<Result<null>> {
  const registry = await readRegistry(root)
  const def = registry.defs[propertyId]
  if (!def) return fail('not-found', 'Property not found.')

  // EVERY collection folder, not just current assigners — a Remove-cache block lives on a
  // sidecar that no longer assigns the id, and pre-cache dormant values may sit on any page (D-6).
  const folders = await allCollectionFolders(root)
  await snapshot(root, propertyId, def, folders)

  for (const folder of folders) {
    // Strip the value from every page under its file lock (shared with the cell-write path).
    for (const file of await listMarkdownFiles(folder)) {
      await rewritePageSerialized(file, (content) => stripPageMember(content, propertyId))
    }
    // Then unassign + purge the Remove-cache on the collection sidecar (JSON, never raced by a
    // cell-write). The .trash snapshot above is the recovery net, so this needn't be atomic.
    const sidecar = await readSidecar(folder, 'collection', pageCollectionSidecar)
    if (!sidecar) continue
    const assigned = (sidecar.properties as string[] | undefined) ?? []
    const cacheAll = isPlainObject(sidecar.property_cache) ? sidecar.property_cache : undefined
    const hadCache = cacheAll !== undefined && propertyId in cacheAll
    if (!assigned.includes(propertyId) && !hadCache) continue
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
    await writeJson(join(folder, SIDECAR_FILENAME.collection), next)
  }
  return removeFromRegistry(root, propertyId)
}
