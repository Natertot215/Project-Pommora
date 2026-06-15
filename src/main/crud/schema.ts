// Property-schema CRUD — generalized over a "schema target" so one set of five ops serves
// both Page Types and Agenda configs (Swift split these across PerTypeSchemaService +
// SingletonSchemaService; here it's one parameterized path). A target supplies its sidecar
// kind + schema, how to enumerate its member files, and how to strip a property value from
// one member (page = frontmatter merge; agenda = JSON property delete). add/rename/reorder
// are sidecar-only writes (property identity is by stable id, so members never move);
// delete + a lossy changeType also strip every member, atomically via SchemaTransaction.
// Errors flow as Result, never thrown.

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import type { z } from 'zod'
import { pageTypeSidecar, agendaConfigSidecar } from '@shared/schemas'
import { defaultStatusSeed, type PropertyDefinition, type PropertyType } from '@shared/properties'
import { isPlainObject } from '@shared/propertyValue'
import { AGENDA_SUFFIX, type AgendaKind } from '@shared/agenda'
import { mintPropertyId } from '../ids'
import { readSidecar, writeSidecar } from '../sidecarIO'
import { SIDECAR_FILENAME, type SidecarKind } from '../paths'
import { splitFrontmatter } from '../readNexus'
import { splitEnvelope, mergeFrontmatter } from '../io/pageFile'
import { serializeJson } from '../io/atomicWrite'
import { listMarkdownFiles, listFilesBySuffix } from '../io/walk'
import { SchemaTransaction } from '../io/schemaTransaction'
import { parseDefinitions, droppingUserRelations, validateDefinition, validateName } from '../properties/schema'
import { nowIso } from './util'
import { ok, fail, type Result } from '@shared/result'

type Sidecar = Record<string, unknown>

/** What a schema-owning entity contributes to the shared CRUD: its sidecar kind + schema,
 *  its member files, and how to strip a property value from one member's content. */
interface SchemaTarget {
  kind: SidecarKind
  schema: z.ZodType
  members: (folder: string) => Promise<string[]>
  /** Stripped content, or null if the member doesn't carry the property (skip it). */
  strip: (content: string, propertyId: string) => string | null
}

// MARK: - Member strip strategies

function stripPageMember(content: string, propertyId: string): string | null {
  const props = splitFrontmatter(content).properties
  if (!isPlainObject(props) || !(propertyId in props)) return null
  const next = { ...props }
  delete next[propertyId]
  const body = splitEnvelope(content).body
  return mergeFrontmatter(content, { properties: next, modified_at: nowIso() }, ['properties', 'modified_at'], body)
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

const PAGE_TARGET: SchemaTarget = {
  kind: 'pageType',
  schema: pageTypeSidecar,
  members: (folder) => listMarkdownFiles(folder),
  strip: stripPageMember
}

function agendaTarget(kind: AgendaKind): SchemaTarget {
  return {
    kind: kind === 'task' ? 'taskConfig' : 'eventConfig',
    schema: agendaConfigSidecar,
    members: (folder) => listFilesBySuffix(folder, AGENDA_SUFFIX[kind]),
    strip: stripAgendaMember
  }
}

// MARK: - Shared core

async function readSchema(target: SchemaTarget, folder: string): Promise<{ sidecar: Sidecar; defs: PropertyDefinition[] } | null> {
  const sidecar = await readSidecar(folder, target.kind, target.schema)
  if (sidecar === null) return null
  const defs = droppingUserRelations(parseDefinitions((sidecar as Sidecar).property_definitions))
  return { sidecar: sidecar as Sidecar, defs }
}

function nextSidecar(sidecar: Sidecar, defs: PropertyDefinition[]): Sidecar {
  return { ...sidecar, property_definitions: defs, modified_at: nowIso() }
}

async function stageMemberStrips(tx: SchemaTransaction, target: SchemaTarget, folder: string, propertyId: string): Promise<void> {
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

async function addProp(target: SchemaTarget, folder: string, def: PropertyDefinition): Promise<Result<{ id: string }>> {
  const s = await readSchema(target, folder)
  if (!s) return fail('not-found', 'Schema not found.', target.kind)
  let candidate: PropertyDefinition = { ...def, id: def.id || mintPropertyId() }
  if (candidate.type === 'status' && candidate.status_groups === undefined) {
    candidate = { ...candidate, status_groups: defaultStatusSeed() }
  }
  const v = validateDefinition(candidate, s.defs)
  if (!v.ok) return v
  await writeSidecar(folder, target.kind, nextSidecar(s.sidecar, [...s.defs, candidate]))
  return ok({ id: candidate.id })
}

async function renameProp(target: SchemaTarget, folder: string, propertyId: string, newName: string): Promise<Result<null>> {
  const s = await readSchema(target, folder)
  if (!s) return fail('not-found', 'Schema not found.', target.kind)
  const idx = s.defs.findIndex((d) => d.id === propertyId)
  if (idx < 0) return fail('not-found', 'Property not found.', target.kind)
  const v = validateName(newName, s.defs, propertyId)
  if (!v.ok) return v
  const next = s.defs.map((d, i) => (i === idx ? { ...d, name: newName } : d))
  await writeSidecar(folder, target.kind, nextSidecar(s.sidecar, next))
  return ok(null)
}

async function reorderProp(target: SchemaTarget, folder: string, propertyId: string, toIndex: number): Promise<Result<null>> {
  const s = await readSchema(target, folder)
  if (!s) return fail('not-found', 'Schema not found.', target.kind)
  const from = s.defs.findIndex((d) => d.id === propertyId)
  if (from < 0) return fail('not-found', 'Property not found.', target.kind)
  const clamped = Math.min(Math.max(toIndex, 0), s.defs.length - 1)
  if (clamped === from) return ok(null)
  const next = [...s.defs]
  const [moved] = next.splice(from, 1)
  next.splice(clamped, 0, moved)
  await writeSidecar(folder, target.kind, nextSidecar(s.sidecar, next))
  return ok(null)
}

async function deleteProp(target: SchemaTarget, folder: string, propertyId: string): Promise<Result<null>> {
  const s = await readSchema(target, folder)
  if (!s) return fail('not-found', 'Schema not found.', target.kind)
  if (!s.defs.some((d) => d.id === propertyId)) return fail('not-found', 'Property not found.', target.kind)
  const next = s.defs.filter((d) => d.id !== propertyId)
  const tx = new SchemaTransaction()
  tx.stage(join(folder, SIDECAR_FILENAME[target.kind]), serializeJson(nextSidecar(s.sidecar, next)))
  await stageMemberStrips(tx, target, folder, propertyId)
  await tx.commit()
  return ok(null)
}

async function changeType(
  target: SchemaTarget,
  folder: string,
  propertyId: string,
  newType: PropertyType,
  opts: { dropConflictingValues?: boolean }
): Promise<Result<null>> {
  const s = await readSchema(target, folder)
  if (!s) return fail('not-found', 'Schema not found.', target.kind)
  const idx = s.defs.findIndex((d) => d.id === propertyId)
  if (idx < 0) return fail('not-found', 'Property not found.', target.kind)
  const next = s.defs.map((d, i) => (i === idx ? { ...d, type: newType } : d))
  if (s.defs[idx].type === newType) {
    await writeSidecar(folder, target.kind, nextSidecar(s.sidecar, next))
    return ok(null)
  }
  if (!opts.dropConflictingValues) {
    return fail('lossy-change-requires-confirmation', 'Changing this property type drops existing values.', target.kind)
  }
  const tx = new SchemaTransaction()
  tx.stage(join(folder, SIDECAR_FILENAME[target.kind]), serializeJson(nextSidecar(s.sidecar, next)))
  await stageMemberStrips(tx, target, folder, propertyId)
  await tx.commit()
  return ok(null)
}

// MARK: - Page Type schema CRUD (the original public surface)

export const addProperty = (typeFolder: string, def: PropertyDefinition) => addProp(PAGE_TARGET, typeFolder, def)
export const renameProperty = (typeFolder: string, propertyId: string, newName: string) =>
  renameProp(PAGE_TARGET, typeFolder, propertyId, newName)
export const reorderProperty = (typeFolder: string, propertyId: string, toIndex: number) =>
  reorderProp(PAGE_TARGET, typeFolder, propertyId, toIndex)
export const deleteProperty = (typeFolder: string, propertyId: string) => deleteProp(PAGE_TARGET, typeFolder, propertyId)
export const changePropertyType = (
  typeFolder: string,
  propertyId: string,
  newType: PropertyType,
  opts: { dropConflictingValues?: boolean } = {}
) => changeType(PAGE_TARGET, typeFolder, propertyId, newType, opts)

// MARK: - Agenda config schema CRUD (same ops, JSON members)

export const addAgendaProperty = (configFolder: string, kind: AgendaKind, def: PropertyDefinition) =>
  addProp(agendaTarget(kind), configFolder, def)
export const renameAgendaProperty = (configFolder: string, kind: AgendaKind, propertyId: string, newName: string) =>
  renameProp(agendaTarget(kind), configFolder, propertyId, newName)
export const reorderAgendaProperty = (configFolder: string, kind: AgendaKind, propertyId: string, toIndex: number) =>
  reorderProp(agendaTarget(kind), configFolder, propertyId, toIndex)
export const deleteAgendaProperty = (configFolder: string, kind: AgendaKind, propertyId: string) =>
  deleteProp(agendaTarget(kind), configFolder, propertyId)
export const changeAgendaPropertyType = (
  configFolder: string,
  kind: AgendaKind,
  propertyId: string,
  newType: PropertyType,
  opts: { dropConflictingValues?: boolean } = {}
) => changeType(agendaTarget(kind), configFolder, propertyId, newType, opts)
