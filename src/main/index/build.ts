// Cold index build — populate the SQLite accelerator from the canonical files. The index
// is off the read path, so this never blocks: it reads the nexus, then writes every row in
// one transaction. better-sqlite3 transactions are synchronous, so all async file I/O
// happens first (collect), then the sync upserts run inside transact(). Mirrors Swift's
// IndexBuilder.populate; ids match the sidecars so a React- and Swift-built index agree.

import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { readNexus } from '../readNexus'
import { splitFrontmatter } from '../readNexus'
import { splitEnvelope } from '../io/pageFile'
import { readSidecar } from '../sidecarIO'
import { pageTypeSidecar, pageCollectionSidecar, pageSetSidecar } from '@shared/schemas'
import { contextTierDir } from '../paths'
import { parseDefinitions } from '../properties/schema'
import { buildLinkIndex } from '../connections/resolve'
import { connectionEdges } from '../connections/edges'
import type { PropertyDefinition } from '@shared/properties'
import type { PageTypeNode, CollectionNode } from '@shared/types'
import { openIndex } from './open'
import { stampSchemaVersion } from './schema'
import { transact, type Db } from './db'
import {
  upsertPageType,
  upsertCollection,
  upsertSet,
  upsertPage,
  upsertContext,
  upsertPropertyDefinition,
  replaceContextLinks,
  replaceConnections
} from './upsert'

const EPOCH = '1970-01-01T00:00:00.000Z'
const str = (v: unknown): string => (typeof v === 'string' ? v : '')
const strArr = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : [])

interface ContextData {
  id: string
  tier: number
  title: string
  icon?: string
}
interface TypeData {
  id: string
  title: string
  icon?: string
  modifiedAt: string
  schemaVersion?: number
  defs: PropertyDefinition[]
}
interface ContainerData {
  id: string
  parentId: string
  title: string
  icon?: string
  modifiedAt: string
  schemaVersion?: number
}
interface PageData {
  id: string
  pageTypeId: string
  collectionId?: string
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
  types: TypeData[]
  collections: ContainerData[]
  sets: ContainerData[]
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

  const allTypes: PageTypeNode[] = [...tree.vaults, ...tree.userSections.flatMap((s) => s.vaults)]
  const types: TypeData[] = []
  const collections: ContainerData[] = []
  const sets: ContainerData[] = []
  const pages: PageData[] = []

  for (const type of allTypes) {
    const typeFolder = join(nexusRoot, type.title)
    const sc = await readSidecar(typeFolder, 'pageType', pageTypeSidecar)
    types.push({
      id: type.id,
      title: type.title,
      icon: type.icon,
      modifiedAt: str(sc?.modified_at) || EPOCH,
      schemaVersion: sc?.schema_version,
      defs: parseDefinitions(sc?.property_definitions)
    })
    for (const page of type.pages) pages.push(await readPageData(nexusRoot, page, type.id))
    for (const coll of type.collections) {
      const collFolder = join(typeFolder, coll.title)
      const csc = await readSidecar(collFolder, 'collection', pageCollectionSidecar)
      collections.push({
        id: coll.id,
        parentId: type.id,
        title: coll.title,
        icon: coll.icon,
        modifiedAt: str(csc?.modified_at) || EPOCH,
        schemaVersion: csc?.schema_version
      })
      for (const page of coll.pages) pages.push(await readPageData(nexusRoot, page, type.id, coll.id))
      for (const set of coll.sets) {
        const ssc = await readSidecar(join(collFolder, set.title), 'set', pageSetSidecar)
        sets.push({
          id: set.id,
          parentId: coll.id,
          title: set.title,
          icon: set.icon,
          modifiedAt: str(ssc?.modified_at) || EPOCH,
          schemaVersion: ssc?.schema_version
        })
        for (const page of set.pages) pages.push(await readPageData(nexusRoot, page, type.id, coll.id, set.id))
      }
    }
  }

  return { contexts, types, collections, sets, pages }
}

async function readPageData(
  nexusRoot: string,
  page: { id: string; title: string; icon?: string; path: string },
  pageTypeId: string,
  collectionId?: string,
  setId?: string
): Promise<PageData> {
  let content = ''
  try {
    content = await readFile(join(nexusRoot, page.path), 'utf8')
  } catch {
    /* unreadable — index it as an empty page (structure still queryable) */
  }
  const fm = splitFrontmatter(content)
  return {
    id: page.id,
    pageTypeId,
    collectionId,
    setId,
    title: page.title,
    icon: page.icon,
    properties: fm.properties ?? {},
    modifiedAt: str(fm.modified_at) || str(fm.created_at) || EPOCH,
    tiers: { 1: strArr(fm.tier1), 2: strArr(fm.tier2), 3: strArr(fm.tier3) },
    body: splitEnvelope(content).body
  }
}

/** The config blob stored in property_definitions.config — same key set as Swift's
 *  PropertyDefinition.indexConfigJSON so the column round-trips identically. */
function configOf(def: PropertyDefinition): Record<string, unknown> {
  const d = def as Record<string, unknown>
  const c: Record<string, unknown> = {}
  for (const k of ['number_format', 'date_includes_time', 'select_options', 'status_groups', 'relation_target', 'accept']) {
    if (d[k] !== undefined) c[k] = d[k]
  }
  return c
}

/** Populate `db` from the nexus (does NOT stamp the version — the caller stamps only after
 *  this resolves successfully, so a failed build never marks the index current). */
export async function buildIndex(db: Db, nexusRoot: string): Promise<void> {
  const data = await collectNexusData(nexusRoot)
  const linkIndex = buildLinkIndex(data.pages.map((p) => ({ id: p.id, title: p.title })))

  transact(db, () => {
    for (const c of data.contexts) upsertContext(db, c)
    for (const t of data.types) {
      upsertPageType(db, t)
      t.defs.forEach((def, position) =>
        upsertPropertyDefinition(db, {
          id: def.id,
          owningTypeId: t.id,
          owningTypeKind: 'page_type',
          name: def.name,
          type: def.type,
          config: configOf(def),
          position,
          modifiedAt: t.modifiedAt
        })
      )
    }
    for (const c of data.collections) upsertCollection(db, { ...c, pageTypeId: c.parentId })
    for (const s of data.sets) upsertSet(db, { ...s, collectionId: s.parentId })
    for (const p of data.pages) {
      upsertPage(db, p)
      const links = [1, 2, 3].flatMap((tier) =>
        p.tiers[tier].map((targetId) => ({
          id: `${p.id}:_tier${tier}:${targetId}`,
          sourceKind: 'page',
          targetId,
          targetKind: 'context',
          propertyId: `_tier${tier}`,
          modifiedAt: p.modifiedAt
        }))
      )
      replaceContextLinks(db, p.id, links)
      const conns = connectionEdges(p.id, p.body, linkIndex).map((e) => ({
        id: `${p.id}:${e.normalizedTitle}`,
        targetId: e.targetId,
        targetTitle: e.normalizedTitle,
        multiplicity: e.multiplicity,
        resolved: e.status === 'resolved',
        modifiedAt: p.modifiedAt
      }))
      replaceConnections(db, p.id, conns)
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
