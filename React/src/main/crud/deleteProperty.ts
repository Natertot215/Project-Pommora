// Global property delete — the one nexus-wide destructive fan-out. Snapshot-first (a
// timestamped JSON of the def + every page value lands in `.trash`, so the scrub is
// recoverable), then one atomic SchemaTransaction strips the value from every assigner's
// pages and drops the id from every assignment, and finally the def leaves the registry.
// The daily non-destructive op is unassign (crud/assignment); this is the rare one.

import { join } from 'node:path'
import { readFile, mkdir, writeFile } from 'node:fs/promises'
import { readRegistry } from '../io/propertiesRegistry'
import { removeFromRegistry } from './registryProperty'
import { assigners } from './assignment'
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

async function snapshot(root: string, propertyId: string, folders: string[]): Promise<void> {
  const registry = await readRegistry(root)
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
    serializeJson({ propertyId, def: registry[propertyId] ?? null, values })
  )
}

export async function deleteProperty(root: string, propertyId: string): Promise<Result<null>> {
  const registry = await readRegistry(root)
  if (!registry[propertyId]) return fail('not-found', 'Property not found.')

  const folders = await assigners(root, propertyId)
  await snapshot(root, propertyId, folders)

  const tx = new SchemaTransaction()
  for (const folder of folders) {
    const sidecar = await readSidecar(folder, 'collection', pageCollectionSidecar)
    if (sidecar) {
      const ids = ((sidecar.properties as string[] | undefined) ?? []).filter((id) => id !== propertyId)
      tx.stage(
        join(folder, SIDECAR_FILENAME.collection),
        serializeJson({ ...sidecar, properties: ids, modified_at: nowIso() })
      )
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
