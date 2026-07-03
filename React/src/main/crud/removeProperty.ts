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
import { applyPropertyValue, isPlainObject, type FileRef, type PropertyValue } from '@shared/propertyValue'
import type { PropertyDefinition } from '@shared/properties'
import { serializeSchemaOp } from './schemaChain'
import { nowIso } from './util'
import { ok, type Result } from '@shared/result'

export function removeProperty(collectionFolder: string, propertyId: string): Promise<Result<null>> {
  return serializeSchemaOp(() => removeInner(collectionFolder, propertyId))
}

async function removeInner(collectionFolder: string, propertyId: string): Promise<Result<null>> {
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
    if (raw === undefined) continue
    // Strip unconditionally; only the CACHE needs identity — an id-less page must not leak
    // the value Remove exists to clear (its value just isn't restorable).
    if (typeof fields.id === 'string') values[fields.id] = raw
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

/** Per-value schema-currency gate — type-DIRECTED, never shape-inferred (breaker H-1): the
 *  shape-blind codec would re-infer a select value like "2024-01-01" or "https://acme.io" as
 *  datetime/url and destroy it, so the RAW on-disk encoding validates against the def's
 *  CURRENT type + options directly. select/status need a live option; multiSelect intersects
 *  (an empty intersection drops). Restore never plants a value the schema can't validate. */
export function reconcileCachedValue(def: PropertyDefinition, raw: unknown): PropertyValue | null {
  const options =
    def.type === 'status'
      ? (def.status_groups ?? []).flatMap((g) => g.options.map((o) => o.value))
      : (def.select_options ?? []).map((o) => o.value)
  switch (def.type) {
    case 'number':
      return typeof raw === 'number' ? { kind: 'number', value: raw } : null
    case 'checkbox':
      return typeof raw === 'boolean' ? { kind: 'checkbox', value: raw } : null
    case 'url':
      return typeof raw === 'string' && raw ? { kind: 'url', value: raw } : null
    case 'datetime':
      return typeof raw === 'string' && raw ? { kind: 'datetime', value: raw } : null
    case 'select':
      return typeof raw === 'string' && options.includes(raw) ? { kind: 'select', value: raw } : null
    case 'status': {
      const v = isPlainObject(raw) && typeof raw.$status === 'string' ? raw.$status : null
      return v !== null && options.includes(v) ? { kind: 'status', value: v } : null
    }
    case 'multi_select': {
      if (!Array.isArray(raw) || !raw.every((x): x is string => typeof x === 'string')) return null
      const kept = raw.filter((v) => options.includes(v))
      return kept.length ? { kind: 'multiSelect', value: kept } : null
    }
    case 'context': {
      if (isPlainObject(raw) && typeof raw.$ctx === 'string') return { kind: 'context', value: [raw.$ctx] }
      if (Array.isArray(raw) && raw.length && raw.every((x) => isPlainObject(x) && typeof x.$ctx === 'string')) {
        return { kind: 'context', value: raw.map((x) => (x as { $ctx: string }).$ctx) }
      }
      return null
    }
    case 'file': {
      if (Array.isArray(raw) && raw.length && raw.every((x) => isPlainObject(x) && typeof x.path === 'string')) {
        return { kind: 'file', value: raw as FileRef[] }
      }
      return null
    }
    default:
      return null // last_edited_time — computed, never restored
  }
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
