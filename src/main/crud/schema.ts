// Property-schema CRUD on a Page Type's sidecar. Mirrors Swift's PerTypeSchemaService
// (five ops) — collapsed: no PerTypeSchemaAdapter protocol, no duplicated singleton
// service, no index-on-write plumbing, no pendingError sink. add/rename/reorder are
// sidecar-only writes (property identity is by stable id, so member pages keyed by that
// id never move). delete + a *lossy* changeType also strip the property's value from
// every member page, so they rewrite the sidecar + all members atomically via
// SchemaTransaction. Errors flow as Result, never thrown.
//
// Agenda config-schema CRUD (`_taskconfig.json` / `_eventconfig.json`) folds in later
// via the agendaEntity factory, reusing these pure transforms with a JSON member strip.

import { readFile, readdir } from 'node:fs/promises'
import { join } from 'node:path'
import { pageTypeSidecar } from '@shared/schemas'
import {
  defaultStatusSeed,
  type PropertyDefinition,
  type PropertyType
} from '@shared/properties'
import { mintPropertyId } from '../ids'
import { readSidecar, writeSidecar } from '../sidecarIO'
import { SIDECAR_FILENAME } from '../paths'
import { splitFrontmatter } from '../readNexus'
import { splitEnvelope, mergeFrontmatter } from '../io/pageFile'
import { serializeJson } from '../io/atomicWrite'
import { SchemaTransaction } from '../io/schemaTransaction'
import {
  parseDefinitions,
  droppingUserRelations,
  validateDefinition,
  validateName
} from '../properties/schema'
import { nowIso } from './util'
import { ok, fail, type Result } from '@shared/result'

const KIND = 'pageType' as const

type Sidecar = Record<string, unknown>

/** The Type's stored, normalized, user-relation-dropped definitions + the full sidecar
 *  object (foreign keys retained) for write-back. null when the sidecar is absent/invalid. */
async function readSchema(typeFolder: string): Promise<{ sidecar: Sidecar; defs: PropertyDefinition[] } | null> {
  const sidecar = await readSidecar(typeFolder, KIND, pageTypeSidecar)
  if (sidecar === null) return null
  const defs = droppingUserRelations(parseDefinitions((sidecar as Sidecar).property_definitions))
  return { sidecar: sidecar as Sidecar, defs }
}

/** The next sidecar object: foreign keys preserved, definitions replaced, modified bumped. */
function nextSidecar(sidecar: Sidecar, defs: PropertyDefinition[]): Sidecar {
  return { ...sidecar, property_definitions: defs, modified_at: nowIso() }
}

/** Add a property to a Type's schema. Mints `prop_<ulid>` when `def.id` is empty; seeds a
 *  default status group set for a status property with none provided. Validates, then a
 *  sidecar-only write (members keyed by id are untouched). */
export async function addProperty(typeFolder: string, def: PropertyDefinition): Promise<Result<{ id: string }>> {
  const s = await readSchema(typeFolder)
  if (!s) return fail('not-found', 'Type schema not found.', KIND)
  let candidate: PropertyDefinition = { ...def, id: def.id || mintPropertyId() }
  if (candidate.type === 'status' && candidate.status_groups === undefined) {
    candidate = { ...candidate, status_groups: defaultStatusSeed() }
  }
  const v = validateDefinition(candidate, s.defs)
  if (!v.ok) return v
  await writeSidecar(typeFolder, KIND, nextSidecar(s.sidecar, [...s.defs, candidate]))
  return ok({ id: candidate.id })
}

/** Rename a property by its stable id (sidecar-only; member files keyed by id untouched). */
export async function renameProperty(typeFolder: string, propertyId: string, newName: string): Promise<Result<null>> {
  const s = await readSchema(typeFolder)
  if (!s) return fail('not-found', 'Type schema not found.', KIND)
  const idx = s.defs.findIndex((d) => d.id === propertyId)
  if (idx < 0) return fail('not-found', 'Property not found.', KIND)
  const v = validateName(newName, s.defs, propertyId)
  if (!v.ok) return v
  const next = s.defs.map((d, i) => (i === idx ? { ...d, name: newName } : d))
  await writeSidecar(typeFolder, KIND, nextSidecar(s.sidecar, next))
  return ok(null)
}

/** Move a property to a new index within the schema (sidecar-only). Index is clamped. */
export async function reorderProperty(typeFolder: string, propertyId: string, toIndex: number): Promise<Result<null>> {
  const s = await readSchema(typeFolder)
  if (!s) return fail('not-found', 'Type schema not found.', KIND)
  const from = s.defs.findIndex((d) => d.id === propertyId)
  if (from < 0) return fail('not-found', 'Property not found.', KIND)
  const clamped = Math.min(Math.max(toIndex, 0), s.defs.length - 1)
  if (clamped === from) return ok(null)
  const next = [...s.defs]
  const [moved] = next.splice(from, 1)
  next.splice(clamped, 0, moved)
  await writeSidecar(typeFolder, KIND, nextSidecar(s.sidecar, next))
  return ok(null)
}

/** Delete a property: remove the schema entry AND strip its value from every member page,
 *  atomically (SchemaTransaction). */
export async function deleteProperty(typeFolder: string, propertyId: string): Promise<Result<null>> {
  const s = await readSchema(typeFolder)
  if (!s) return fail('not-found', 'Type schema not found.', KIND)
  if (!s.defs.some((d) => d.id === propertyId)) return fail('not-found', 'Property not found.', KIND)
  const next = s.defs.filter((d) => d.id !== propertyId)
  const tx = new SchemaTransaction()
  tx.stage(join(typeFolder, SIDECAR_FILENAME[KIND]), serializeJson(nextSidecar(s.sidecar, next)))
  await stageMemberStrips(tx, typeFolder, propertyId)
  await tx.commit()
  return ok(null)
}

/** Change a property's type. Lossless (same type) is a sidecar-only bump. A lossy change
 *  requires `dropConflictingValues` (else it returns a confirmation-required error) and
 *  then strips the property's value from every member page atomically. */
export async function changePropertyType(
  typeFolder: string,
  propertyId: string,
  newType: PropertyType,
  opts: { dropConflictingValues?: boolean } = {}
): Promise<Result<null>> {
  const s = await readSchema(typeFolder)
  if (!s) return fail('not-found', 'Type schema not found.', KIND)
  const idx = s.defs.findIndex((d) => d.id === propertyId)
  if (idx < 0) return fail('not-found', 'Property not found.', KIND)
  const next = s.defs.map((d, i) => (i === idx ? { ...d, type: newType } : d))
  if (s.defs[idx].type === newType) {
    await writeSidecar(typeFolder, KIND, nextSidecar(s.sidecar, next))
    return ok(null)
  }
  if (!opts.dropConflictingValues) {
    return fail('lossy-change-requires-confirmation', 'Changing this property type drops existing values.', KIND)
  }
  const tx = new SchemaTransaction()
  tx.stage(join(typeFolder, SIDECAR_FILENAME[KIND]), serializeJson(nextSidecar(s.sidecar, next)))
  await stageMemberStrips(tx, typeFolder, propertyId)
  await tx.commit()
  return ok(null)
}

// MARK: - Member-file strip

/** All member `.md` pages under a Type folder (pages live directly or nested in
 *  Collections/Sets). */
async function memberPageFiles(typeFolder: string): Promise<string[]> {
  let rels: string[]
  try {
    rels = await readdir(typeFolder, { recursive: true })
  } catch {
    return []
  }
  return rels.filter((r) => r.endsWith('.md')).map((r) => join(typeFolder, r))
}

/** Stage a property-value strip for every member that carries `propertyId`, preserving
 *  the body + sibling properties + foreign keys. Resilient (mirrors MemberFileStrip): a
 *  member that's unreadable or doesn't carry the property is skipped (a file we can't
 *  read can't hold the value, so skipping is lossless). */
async function stageMemberStrips(tx: SchemaTransaction, typeFolder: string, propertyId: string): Promise<void> {
  for (const file of await memberPageFiles(typeFolder)) {
    let content: string
    try {
      content = await readFile(file, 'utf8')
    } catch {
      continue
    }
    const props = splitFrontmatter(content).properties
    if (props === null || typeof props !== 'object' || Array.isArray(props)) continue
    const record = props as Record<string, unknown>
    if (!(propertyId in record)) continue
    const nextProps = { ...record }
    delete nextProps[propertyId]
    const body = splitEnvelope(content).body
    tx.stage(
      file,
      mergeFrontmatter(content, { properties: nextProps, modified_at: nowIso() }, ['properties', 'modified_at'], body)
    )
  }
}
