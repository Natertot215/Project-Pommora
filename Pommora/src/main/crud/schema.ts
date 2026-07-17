// Agenda property-schema CRUD — generalized over a "schema target" (kind + schema + member
// enumeration + per-member value strip). Collections left this path in PropertiesV2: their
// defs live in the nexus-wide registry (crud/registryProperty) with sidecar assignment ids
// (crud/assignment); only Agenda configs still hold inline `property_definitions`.
// `stripPageMember` stays exported — the registry's global delete fan-out reuses it.
// add/rename/reorder are sidecar-only writes; delete + a lossy changeType also strip every
// member, atomically via SchemaTransaction. Errors flow as Result, never thrown.

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import type { z } from 'zod'
import { agendaConfigSidecar } from '@shared/schemas'
import {
  defaultSelectSeed,
  defaultStatusSeed,
  type PropertyDefinition,
  type PropertyType,
} from '@shared/properties'
import { isPlainObject } from '@shared/propertyValue'
import { AGENDA_SUFFIX, type AgendaKind } from '@shared/agenda'
import { mintPropertyId } from '../ids'
import { readSidecar, writeSidecar } from '../sidecarIO'
import { SIDECAR_FILENAME, type SidecarKind } from '../paths'
import { splitFrontmatter } from '../readNexus'
import { splitEnvelope, mergeFrontmatter } from '../io/pageFile'
import { serializeJson } from '../io/atomicWrite'
import { listFilesBySuffix } from '../io/walk'
import { SchemaTransaction } from '../io/schemaTransaction'
import {
  parseDefinitions,
  droppingUserContexts,
  validateDefinition,
  validateName,
} from '../properties/schema'
import { nowIso } from './util'
import { ok, fail, type Result } from '@shared/result'

type Sidecar = Record<string, unknown>

/** What a schema-owning entity contributes to the shared CRUD: its sidecar kind + schema,
 *  its member files, and how to strip a property value from one member's content. */
interface SchemaTarget {
  kind: SidecarKind
  schema: z.ZodType
  /** The sidecar JSON key holding the schema array. Collections use Swift's `properties`;
   *  agenda configs use `property_definitions`. */
  schemaKey: string
  members: (folder: string) => Promise<string[]>
  /** Stripped content, or null if the member doesn't carry the property (skip it). */
  strip: (content: string, propertyId: string) => string | null
}

// MARK: - Member strip strategies

export function stripPageMember(content: string, propertyId: string): string | null {
  const props = splitFrontmatter(content).properties
  if (!isPlainObject(props) || !(propertyId in props)) return null
  const next = { ...props }
  delete next[propertyId]
  const body = splitEnvelope(content).body
  return mergeFrontmatter(
    content,
    { properties: next, modified_at: nowIso() },
    ['properties', 'modified_at'],
    body,
  )
}

function stripAgendaMember(content: string, propertyId: string): string | null {
  let raw: unknown
  try {
    raw = JSON.parse(content)
  } catch {
    return null
  }
  if (!isPlainObject(raw)) return null
  const props = raw.properties
  if (!isPlainObject(props) || !(propertyId in props)) return null
  const next = { ...props }
  delete next[propertyId]
  return serializeJson({ ...raw, properties: next, modified_at: nowIso() })
}

function agendaTarget(kind: AgendaKind): SchemaTarget {
  return {
    kind: kind === 'task' ? 'taskConfig' : 'eventConfig',
    schema: agendaConfigSidecar,
    schemaKey: 'property_definitions',
    members: (folder) => listFilesBySuffix(folder, AGENDA_SUFFIX[kind]),
    strip: stripAgendaMember,
  }
}

// MARK: - Shared core

async function readSchema(
  target: SchemaTarget,
  folder: string,
): Promise<{ sidecar: Sidecar; defs: PropertyDefinition[] } | null> {
  const sidecar = await readSidecar(folder, target.kind, target.schema)
  if (sidecar === null) return null
  const defs = droppingUserContexts(parseDefinitions((sidecar as Sidecar)[target.schemaKey]))
  return { sidecar: sidecar as Sidecar, defs }
}

function nextSidecar(sidecar: Sidecar, defs: PropertyDefinition[], schemaKey: string): Sidecar {
  return { ...sidecar, [schemaKey]: defs, modified_at: nowIso() }
}

async function stageMemberStrips(
  tx: SchemaTransaction,
  target: SchemaTarget,
  folder: string,
  propertyId: string,
): Promise<void> {
  for (const file of await target.members(folder)) {
    let content: string
    try {
      content = await readFile(file, 'utf8')
    } catch {
      continue
    }
    const stripped = target.strip(content, propertyId)
    if (stripped !== null) tx.stage(file, stripped)
  }
}

async function addProp(
  target: SchemaTarget,
  folder: string,
  def: PropertyDefinition,
): Promise<Result<{ id: string }>> {
  const s = await readSchema(target, folder)
  if (!s) return fail('not-found', 'Schema not found.', target.kind)
  let candidate: PropertyDefinition = { ...def, id: def.id || mintPropertyId() }
  if (candidate.type === 'status' && candidate.status_groups === undefined) {
    candidate = { ...candidate, status_groups: defaultStatusSeed() }
  }
  if (
    (candidate.type === 'select' || candidate.type === 'multi_select') &&
    (candidate.select_options === undefined || candidate.select_options.length === 0)
  ) {
    candidate = { ...candidate, select_options: defaultSelectSeed() }
  }
  const v = validateDefinition(candidate, s.defs)
  if (!v.ok) return v
  await writeSidecar(
    folder,
    target.kind,
    nextSidecar(s.sidecar, [...s.defs, candidate], target.schemaKey),
  )
  return ok({ id: candidate.id })
}

async function renameProp(
  target: SchemaTarget,
  folder: string,
  propertyId: string,
  newName: string,
): Promise<Result<null>> {
  const s = await readSchema(target, folder)
  if (!s) return fail('not-found', 'Schema not found.', target.kind)
  const idx = s.defs.findIndex((d) => d.id === propertyId)
  if (idx < 0) return fail('not-found', 'Property not found.', target.kind)
  const v = validateName(newName, s.defs, propertyId)
  if (!v.ok) return v
  const next = s.defs.map((d, i) => (i === idx ? { ...d, name: newName } : d))
  await writeSidecar(folder, target.kind, nextSidecar(s.sidecar, next, target.schemaKey))
  return ok(null)
}

async function reorderProp(
  target: SchemaTarget,
  folder: string,
  propertyId: string,
  toIndex: number,
): Promise<Result<null>> {
  const s = await readSchema(target, folder)
  if (!s) return fail('not-found', 'Schema not found.', target.kind)
  const from = s.defs.findIndex((d) => d.id === propertyId)
  if (from < 0) return fail('not-found', 'Property not found.', target.kind)
  const clamped = Math.min(Math.max(toIndex, 0), s.defs.length - 1)
  if (clamped === from) return ok(null)
  const next = [...s.defs]
  const [moved] = next.splice(from, 1)
  next.splice(clamped, 0, moved)
  await writeSidecar(folder, target.kind, nextSidecar(s.sidecar, next, target.schemaKey))
  return ok(null)
}

async function deleteProp(
  target: SchemaTarget,
  folder: string,
  propertyId: string,
): Promise<Result<null>> {
  const s = await readSchema(target, folder)
  if (!s) return fail('not-found', 'Schema not found.', target.kind)
  if (!s.defs.some((d) => d.id === propertyId))
    return fail('not-found', 'Property not found.', target.kind)
  const next = s.defs.filter((d) => d.id !== propertyId)
  const tx = new SchemaTransaction()
  tx.stage(
    join(folder, SIDECAR_FILENAME[target.kind]),
    serializeJson(nextSidecar(s.sidecar, next, target.schemaKey)),
  )
  await stageMemberStrips(tx, target, folder, propertyId)
  await tx.commit()
  return ok(null)
}

async function changeType(
  target: SchemaTarget,
  folder: string,
  propertyId: string,
  newType: PropertyType,
  opts: { dropConflictingValues?: boolean },
): Promise<Result<null>> {
  const s = await readSchema(target, folder)
  if (!s) return fail('not-found', 'Schema not found.', target.kind)
  const idx = s.defs.findIndex((d) => d.id === propertyId)
  if (idx < 0) return fail('not-found', 'Property not found.', target.kind)
  const next = s.defs.map((d, i) => (i === idx ? { ...d, type: newType } : d))
  if (s.defs[idx].type === newType) {
    await writeSidecar(folder, target.kind, nextSidecar(s.sidecar, next, target.schemaKey))
    return ok(null)
  }
  if (!opts.dropConflictingValues) {
    return fail(
      'lossy-change-requires-confirmation',
      'Changing this property type drops existing values.',
      target.kind,
    )
  }
  const tx = new SchemaTransaction()
  tx.stage(
    join(folder, SIDECAR_FILENAME[target.kind]),
    serializeJson(nextSidecar(s.sidecar, next, target.schemaKey)),
  )
  await stageMemberStrips(tx, target, folder, propertyId)
  await tx.commit()
  return ok(null)
}

// MARK: - Agenda config schema CRUD (same ops, JSON members)

export const addAgendaProperty = (
  configFolder: string,
  kind: AgendaKind,
  def: PropertyDefinition,
) => addProp(agendaTarget(kind), configFolder, def)
export const renameAgendaProperty = (
  configFolder: string,
  kind: AgendaKind,
  propertyId: string,
  newName: string,
) => renameProp(agendaTarget(kind), configFolder, propertyId, newName)
export const reorderAgendaProperty = (
  configFolder: string,
  kind: AgendaKind,
  propertyId: string,
  toIndex: number,
) => reorderProp(agendaTarget(kind), configFolder, propertyId, toIndex)
export const deleteAgendaProperty = (configFolder: string, kind: AgendaKind, propertyId: string) =>
  deleteProp(agendaTarget(kind), configFolder, propertyId)
export const changeAgendaPropertyType = (
  configFolder: string,
  kind: AgendaKind,
  propertyId: string,
  newType: PropertyType,
  opts: { dropConflictingValues?: boolean } = {},
) => changeType(agendaTarget(kind), configFolder, propertyId, newType, opts)
