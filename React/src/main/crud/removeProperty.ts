// Remove (C-3) — the daily non-destructive lifecycle op, and its restore half. Remove strips
// the property's value from every member page, caches { pageId: raw } on the Collection's
// sidecar, and unassigns — ONE SchemaTransaction (E-3), so no partial state survives a
// failure. Re-assigning restores each cached value that still conforms to the def's CURRENT
// type + options (per-value reconciliation); the global Delete purges these caches (D-6).

import { join } from 'node:path'
import { readFile } from 'node:fs/promises'
import { SchemaTransaction } from '../io/schemaTransaction'
import { stripPageMember } from './schema'
import { readSidecar } from '../sidecarIO'
import { pageCollectionSidecar } from '@shared/schemas'
import { listMarkdownFiles } from '../io/walk'
import { SIDECAR_FILENAME } from '../paths'
import { serializeJson } from '../io/atomicWrite'
import { readFrontmatterFields, mergeFrontmatter, splitEnvelope } from '../io/pageFile'
import { readRegistry } from '../io/propertiesRegistry'
import {
  parsePropertyValue,
  applyPropertyValue,
  isPlainObject,
  type PropertyValue
} from '@shared/propertyValue'
import type { PropertyDefinition } from '@shared/properties'
import { nowIso } from './util'
import { ok, type Result } from '@shared/result'

export async function removeProperty(collectionFolder: string, propertyId: string): Promise<Result<null>> {
  const sidecar = await readSidecar(collectionFolder, 'collection', pageCollectionSidecar)
  const ids = (sidecar?.properties as string[] | undefined) ?? []
  if (!sidecar || !ids.includes(propertyId)) return ok(null) // not assigned → no-op (E-6)

  const tx = new SchemaTransaction()
  const values: Record<string, unknown> = {}
  for (const file of await listMarkdownFiles(collectionFolder)) {
    let content: string
    try {
      content = await readFile(file, 'utf8')
    } catch {
      continue
    }
    const fields = readFrontmatterFields(content)
    const raw = isPlainObject(fields.properties) ? fields.properties[propertyId] : undefined
    if (raw === undefined || typeof fields.id !== 'string') continue
    values[fields.id] = raw
    const stripped = stripPageMember(content, propertyId)
    if (stripped !== null) tx.stage(file, stripped)
  }
  const cache = { ...(sidecar.property_cache as Record<string, unknown> | undefined) }
  cache[propertyId] = { removed_at: nowIso(), values }
  tx.stage(
    join(collectionFolder, SIDECAR_FILENAME.collection),
    serializeJson({
      ...sidecar,
      properties: ids.filter((id) => id !== propertyId),
      property_cache: cache,
      modified_at: nowIso()
    })
  )
  await tx.commit()
  return ok(null)
}

const KIND_FOR_TYPE: Record<string, PropertyValue['kind'][]> = {
  number: ['number'],
  checkbox: ['checkbox'],
  datetime: ['datetime'],
  url: ['url'],
  select: ['select'],
  status: ['status'],
  multi_select: ['multiSelect'],
  context: ['context'],
  file: ['file']
}

/** Per-value schema-currency gate: the cached value's kind must match the def's CURRENT
 *  type, and select/status values must be live options (multiSelect intersects; an empty
 *  intersection drops). Restore never plants a value the current schema can't validate. */
export function reconcileCachedValue(def: PropertyDefinition, raw: unknown): PropertyValue | null {
  let parsed: PropertyValue
  try {
    parsed = parsePropertyValue(raw)
  } catch {
    return null
  }
  if (parsed.kind === 'null' || !(KIND_FOR_TYPE[def.type] ?? []).includes(parsed.kind)) return null
  const options =
    def.type === 'status'
      ? (def.status_groups ?? []).flatMap((g) => g.options.map((o) => o.value))
      : (def.select_options ?? []).map((o) => o.value)
  if (parsed.kind === 'select' || parsed.kind === 'status') {
    return options.includes(parsed.value) ? parsed : null
  }
  if (parsed.kind === 'multiSelect') {
    const kept = parsed.value.filter((v) => options.includes(v))
    return kept.length ? { kind: 'multiSelect', value: kept } : null
  }
  return parsed
}

/** Restore the Remove-cache on re-assign: write each reconciled value back to the page
 *  (matched by frontmatter id) that held it — deleted/moved-out pages drop their entries —
 *  and clear the block. ONE SchemaTransaction. No block → no-op. */
export async function restoreCachedValues(
  root: string,
  collectionFolder: string,
  propertyId: string
): Promise<Result<null>> {
  const sidecar = await readSidecar(collectionFolder, 'collection', pageCollectionSidecar)
  if (!sidecar) return ok(null)
  const cacheAll = isPlainObject(sidecar.property_cache) ? sidecar.property_cache : undefined
  const block = cacheAll?.[propertyId]
  if (!isPlainObject(block) || !isPlainObject(block.values)) return ok(null)

  const def = (await readRegistry(root)).defs[propertyId]
  const tx = new SchemaTransaction()
  if (def) {
    const byId = new Map<string, { file: string; content: string }>()
    for (const file of await listMarkdownFiles(collectionFolder)) {
      let content: string
      try {
        content = await readFile(file, 'utf8')
      } catch {
        continue
      }
      const id = readFrontmatterFields(content).id
      if (typeof id === 'string') byId.set(id, { file, content })
    }
    for (const [pageId, raw] of Object.entries(block.values)) {
      const page = byId.get(pageId)
      if (!page) continue
      const value = reconcileCachedValue(def, raw)
      if (value === null) continue
      const fields = readFrontmatterFields(page.content)
      const properties = applyPropertyValue(fields.properties, propertyId, value)
      tx.stage(
        page.file,
        mergeFrontmatter(page.content, { properties, modified_at: nowIso() }, ['properties', 'modified_at'], splitEnvelope(page.content).body)
      )
    }
  }
  const cache = { ...cacheAll }
  delete cache[propertyId]
  const nextSidecar: Record<string, unknown> = { ...sidecar, property_cache: cache, modified_at: nowIso() }
  if (Object.keys(cache).length === 0) delete nextSidecar.property_cache
  tx.stage(join(collectionFolder, SIDECAR_FILENAME.collection), serializeJson(nextSidecar))
  await tx.commit()
  return ok(null)
}
