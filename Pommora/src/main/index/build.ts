// Cold index build — populate the SQLite accelerator from the canonical files. The index
// is off the read path, so this never blocks: it reads the nexus, then writes every row in
// one transaction. better-sqlite3 transactions are synchronous, so all async file I/O
// happens first (collect), then the sync upserts run inside transact(). Mirrors Swift's
// IndexBuilder.populate; ids match the sidecars so a React- and Swift-built index agree.

import { readFile, readdir, stat } from 'node:fs/promises'
import { join } from 'node:path'
import { readNexus } from '../readNexus'
import { splitFrontmatter } from '../readNexus'
import { splitEnvelope } from '../io/pageFile'
import { readSidecar } from '../sidecarIO'
import { pageCollectionSidecar, pageSetSidecar } from '@shared/schemas'
import { SIDECAR_FILENAME } from '../paths'
import { agendaTask, agendaEvent, AGENDA_SUFFIX } from '@shared/agenda'
import { orderedDefs, readRegistry } from '../io/propertiesRegistry'
import { nowIso } from '../crud/util'
import { TIER_LEVELS, tierFieldName, tierPropertyId } from '@shared/properties'
import { buildLinkIndex } from '../connections/resolve'
import { connectionEdges } from '../connections/edges'
import { normalizeTitle } from '@shared/connections'
import { pathExists } from './../crud/util'
import type { PropertyDefinition } from '@shared/properties'
import type { CollectionNode, SetNode } from '@shared/types'
import { openIndex } from './open'
import { stampSchemaVersion } from './schema'
import { transact, type Db } from './db'
import { listBlockBodies } from '../blocks'
import {
  upsertCollection,
  upsertSet,
  upsertPage,
  upsertContext,
  upsertPropertyDefinition,
  upsertAgendaTask,
  upsertAgendaEvent,
  replaceContextLinks,
  replaceConnections,
  replaceBlockConnections
} from './upsert'

const EPOCH = '1970-01-01T00:00:00.000Z'
const str = (v: unknown): string => (typeof v === 'string' ? v : '')

/** Effective modified_at, matching Swift's load-time resolution: the stored stamp wins,
 *  else the file's own mtime (so adopted entities lacking a stamp sort by real recency
 *  instead of 1970), else created_at, else epoch. Only stats when the stamp is absent. */
async function resolveModifiedAt(stored: unknown, fallbackFile: string, created?: unknown): Promise<string> {
  const storedStr = str(stored)
  if (storedStr) return storedStr
  try {
    return (await stat(fallbackFile)).mtime.toISOString()
  } catch {
    return str(created) || EPOCH
  }
}
const strArr = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : [])

interface ContextData {
  id: string
  tier: number
  title: string
  icon?: string
}
interface CollectionData {
  id: string
  title: string
  icon?: string
  modifiedAt: string
  schemaVersion?: number
}
interface SetData {
  id: string
  parentCollectionId?: string
  parentSetId?: string
  title: string
  icon?: string
  modifiedAt: string
  schemaVersion?: number
}
interface PageData {
  id: string
  collectionId: string
  setId?: string
  title: string
  icon?: string
  properties: unknown
  modifiedAt: string
  tiers: Record<number, string[]>
  body: string
}
interface NexusData {
  contexts: ContextData[]
  collections: CollectionData[]
  sets: SetData[]
  pages: PageData[]
}

/** Read every canonical file the index needs (async). Folder paths are reconstructed from
 *  titles (filename = title); container modified_at/schema_version come from the sidecars
 *  readNexus already parsed (re-read here until the readNexus refactor exposes them). */
async function collectNexusData(nexusRoot: string): Promise<NexusData> {
  const tree = await readNexus(nexusRoot)

  const contexts: ContextData[] = [
    ...tree.contexts.areas.map((a) => ({ id: a.id, tier: 1, title: a.title, icon: a.icon })),
    ...tree.contexts.topics.map((t) => ({ id: t.id, tier: 2, title: t.title, icon: t.icon })),
    ...tree.contexts.projects.map((p) => ({ id: p.id, tier: 3, title: p.title, icon: p.icon }))
  ]

  const allCollections: CollectionNode[] = [
    ...(tree.collections ?? []),
    ...tree.userSections.flatMap((s) => s.collections ?? [])
  ]
  const collections: CollectionData[] = []
  const sets: SetData[] = []
  const pages: PageData[] = []

  // Recurse a Set subtree (Model A): each Set references exactly one parent — its Collection
  // (depth-1) or its parent Set (deeper); every page records the owning top Collection +
  // its immediate Set. Pages at the Collection root carry no setId.
  const walkSet = async (
    node: SetNode,
    topCollectionId: string,
    parent: { collectionId?: string; setId?: string }
  ): Promise<void> => {
    const ssc = await readSidecar(join(nexusRoot, node.path), 'set', pageSetSidecar)
    sets.push({
      id: node.id,
      parentCollectionId: parent.collectionId,
      parentSetId: parent.setId,
      title: node.title,
      icon: node.icon,
      modifiedAt: await resolveModifiedAt(ssc?.modified_at, join(nexusRoot, node.path, SIDECAR_FILENAME.set)),
      schemaVersion: ssc?.schema_version
    })
    for (const page of node.pages) pages.push(await readPageData(nexusRoot, page, topCollectionId, node.id))
    for (const child of node.sets ?? []) await walkSet(child, topCollectionId, { setId: node.id })
  }

  for (const coll of allCollections) {
    const csc = await readSidecar(join(nexusRoot, coll.path), 'collection', pageCollectionSidecar)
    collections.push({
      id: coll.id,
      title: coll.title,
      icon: coll.icon,
      modifiedAt: await resolveModifiedAt(csc?.modified_at, join(nexusRoot, coll.path, SIDECAR_FILENAME.collection)),
      schemaVersion: csc?.schema_version
    })
    for (const page of coll.pages) pages.push(await readPageData(nexusRoot, page, coll.id))
    for (const set of coll.sets) await walkSet(set, coll.id, { collectionId: coll.id })
  }

  return { contexts, collections, sets, pages }
}

async function readPageData(
  nexusRoot: string,
  page: { id: string; title: string; icon?: string; path: string },
  collectionId: string,
  setId?: string
): Promise<PageData> {
  const abs = join(nexusRoot, page.path)
  let content = ''
  try {
    content = await readFile(abs, 'utf8')
  } catch {
    /* unreadable — index it as an empty page (structure still queryable) */
  }
  const fm = splitFrontmatter(content)
  return {
    id: page.id,
    collectionId,
    setId,
    title: page.title,
    icon: page.icon,
    properties: fm.properties ?? {},
    modifiedAt: await resolveModifiedAt(fm.modified_at, abs, fm.created_at),
    tiers: readTiers(fm),
    body: splitEnvelope(content).body
  }
}

/** The config blob stored in property_definitions.config — same key set as Swift's
 *  PropertyDefinition.indexConfigJSON so the column round-trips identically. */
function configOf(def: PropertyDefinition): Record<string, unknown> {
  const d = def as Record<string, unknown>
  const c: Record<string, unknown> = {}
  for (const k of ['number_format', 'date_includes_time', 'select_options', 'status_groups', 'context_target', 'accept']) {
    if (d[k] !== undefined) c[k] = d[k]
  }
  return c
}

interface AgendaItemData {
  id: string
  title: string
  icon?: string
  dueAt?: string
  startAt?: string
  endAt?: string
  properties: unknown
  modifiedAt: string
  tiers: Record<number, string[]>
}
interface AgendaData {
  tasks: AgendaItemData[]
  events: AgendaItemData[]
}

/** tier level → the coarse entity-kind string stored in context_links.target_kind, matching
 *  Swift's RelationTargetKind.string(from: .contextTier(n)). NOTE: "context_tier" is the
 *  context_target *config* discriminant, NOT this column — the column is the tier entity. */
const TIER_TARGET_KIND: Record<number, string> = { 1: 'area', 2: 'topic', 3: 'project' }

/** A page/agenda item's tier links read off its frontmatter as `{ level: ids }`. */
function readTiers(fm: Record<string, unknown>): Record<number, string[]> {
  const tiers: Record<number, string[]> = {}
  for (const level of TIER_LEVELS) tiers[level] = strArr(fm[tierFieldName(level)])
  return tiers
}

/** One context_links row per tier value — shared by pages + agenda items. */
function tierLinks(sourceId: string, sourceKind: string, tiers: Record<number, string[]>, modifiedAt: string) {
  return TIER_LEVELS.flatMap((tier) =>
    tiers[tier].map((targetId) => ({
      id: `${sourceId}:${tierPropertyId(tier)}:${targetId}`,
      sourceKind,
      targetId,
      targetKind: TIER_TARGET_KIND[tier] ?? 'context',
      propertyId: tierPropertyId(tier),
      modifiedAt
    }))
  )
}

/** Read agenda items. Agenda folders are discovered at the nexus root by the presence of
 *  `_taskconfig.json` / `_eventconfig.json` (readNexus discovers but does not surface them,
 *  so the index walks them directly). Their config schemas are NOT indexed — agenda defs
 *  live in the config sidecars, outside the nexus-wide registry (D-1). */
async function collectAgenda(nexusRoot: string): Promise<AgendaData> {
  const tasks: AgendaItemData[] = []
  const events: AgendaItemData[] = []
  let dirs: string[]
  try {
    dirs = (await readdir(nexusRoot, { withFileTypes: true })).filter((e) => e.isDirectory()).map((e) => e.name)
  } catch {
    return { tasks, events }
  }
  for (const name of dirs) {
    const folder = join(nexusRoot, name)
    const isTask = await pathExists(join(folder, SIDECAR_FILENAME.taskConfig))
    const isEvent = !isTask && (await pathExists(join(folder, SIDECAR_FILENAME.eventConfig)))
    if (!isTask && !isEvent) continue

    const suffix = isTask ? AGENDA_SUFFIX.task : AGENDA_SUFFIX.event
    let files: string[]
    try {
      files = (await readdir(folder)).filter((f) => f.endsWith(suffix))
    } catch {
      continue
    }
    for (const f of files) {
      let content = ''
      try {
        content = await readFile(join(folder, f), 'utf8')
      } catch {
        continue
      }
      const parsed = (isTask ? agendaTask : agendaEvent).safeParse(JSON.parse(content || '{}'))
      if (!parsed.success) continue
      const item = parsed.data as Record<string, unknown>
      const common = {
        id: str(item.id),
        title: f.slice(0, -suffix.length),
        icon: typeof item.icon === 'string' ? item.icon : undefined,
        properties: item.properties ?? {},
        modifiedAt: await resolveModifiedAt(item.modified_at, join(folder, f), item.created_at),
        tiers: readTiers(item)
      }
      if (isTask) tasks.push({ ...common, dueAt: typeof item.due_at === 'string' ? item.due_at : undefined })
      else events.push({ ...common, startAt: str(item.start_at) || EPOCH, endAt: str(item.end_at) || EPOCH })
    }
  }
  return { tasks, events }
}

/** Populate `db` from the nexus (does NOT stamp the version — the caller stamps only after
 *  this resolves successfully, so a failed build never marks the index current). */
export async function buildIndex(db: Db, nexusRoot: string): Promise<void> {
  const data = await collectNexusData(nexusRoot)
  const agenda = await collectAgenda(nexusRoot)
  const registry = await readRegistry(nexusRoot)
  const linkIndex = buildLinkIndex(data.pages.map((p) => ({ id: p.id, title: p.title })))
  // Block bodies are read async (off the sync transaction), then their edges upserted inside it.
  const blockBodies = await listBlockBodies(nexusRoot)

  transact(db, () => {
    for (const c of data.contexts) upsertContext(db, c)
    for (const c of data.collections) upsertCollection(db, c)
    // property_definitions mirrors the nexus-wide registry, one row per def (no owner —
    // assignment lives on the collection sidecars; agenda defs stay out per D-1).
    // `position` rides the nexus-wide cosmetic order — the same rule readNexus exposes.
    orderedDefs(registry).forEach((def, position) =>
      upsertPropertyDefinition(db, {
        id: def.id,
        name: def.name,
        type: def.type,
        config: configOf(def),
        position,
        modifiedAt: nowIso()
      })
    )
    for (const s of data.sets) upsertSet(db, s)
    for (const p of data.pages) {
      upsertPage(db, p)
      replaceContextLinks(db, p.id, tierLinks(p.id, 'page', p.tiers, p.modifiedAt))
      // Skip self-links (a page linking its own title) — matches Swift's insertConnections.
      const selfKey = normalizeTitle(p.title)
      const conns = connectionEdges(p.id, p.body, linkIndex)
        .filter((e) => e.normalizedTitle !== selfKey)
        .map((e) => ({
          id: `${p.id}:${e.normalizedTitle}`,
          targetId: e.targetId,
          targetTitle: e.normalizedTitle,
          multiplicity: e.multiplicity,
          resolved: e.status === 'resolved',
          modifiedAt: p.modifiedAt
        }))
      replaceConnections(db, p.id, conns)
    }

    // Markdown-block [[links]] are block-source edges (D-11 bodies carry no title, so no self-link
    // to skip). Keyed by the block's ulid, resolved against the same page link index.
    for (const blk of blockBodies) {
      const conns = connectionEdges(blk.id, blk.body, linkIndex).map((e) => ({
        id: `${blk.id}:${e.normalizedTitle}`,
        targetId: e.targetId,
        targetTitle: e.normalizedTitle,
        multiplicity: e.multiplicity,
        resolved: e.status === 'resolved',
        modifiedAt: blk.modifiedAt
      }))
      replaceBlockConnections(db, blk.id, conns)
    }

    for (const t of agenda.tasks) {
      upsertAgendaTask(db, t)
      replaceContextLinks(db, t.id, tierLinks(t.id, 'agenda_task', t.tiers, t.modifiedAt))
    }
    for (const ev of agenda.events) {
      upsertAgendaEvent(db, { ...ev, startAt: ev.startAt ?? EPOCH, endAt: ev.endAt ?? EPOCH })
      replaceContextLinks(db, ev.id, tierLinks(ev.id, 'agenda_event', ev.tiers, ev.modifiedAt))
    }
  })
}

/** Open the per-nexus index and cold-build it if needed, stamping the version only on a
 *  successful build. Returns the ready db, or null when the index can't be opened (the
 *  caller degrades to file-only reads). The realistic entry point. */
export async function rebuildIndex(nexusRoot: string): Promise<Db | null> {
  const opened = openIndex(nexusRoot)
  if (!opened) return null
  if (opened.needsRebuild) {
    await buildIndex(opened.db, nexusRoot)
    stampSchemaVersion(opened.db)
  }
  return opened.db
}
