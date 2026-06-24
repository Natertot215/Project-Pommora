// The whole read engine: one recursive, read-only walk of a nexus root.
// Supports BOTH the sidecar-driven path (`.nexus/` + per-folder sidecars) and
// the structure-classification path (raw/un-adopted folders, e.g. ~/test).
// No file is ever opened for writing.

import { readdir, readFile } from 'node:fs/promises'
import { basename, join } from 'node:path'
import { parse as parseYaml } from 'yaml'
import type {
  AccentSetting,
  AreaColor,
  AreaNode,
  CollectionNode,
  NexusTree,
  PageNode,
  PageTypeNode,
  ProjectNode,
  SavedNode,
  SetNode,
  TopicNode,
  UserSection
} from '@shared/types'
import { ACCENT_COLORS, AREA_COLORS, DEFAULT_ACCENT, DEFAULT_LABELS } from '@shared/types'
import { adoptedId } from './ids'
import { pathExists, readJsonObject } from './io/atomicWrite'
import { asString, asStringArray, basenameNoMd } from './coerce'
import { shouldSkipDir } from './exclusion'
import { resolveOrder } from './order'
import {
  AGENDA_FOLDER_NAMES,
  contextTierDir,
  NEXUS_CONFIG_FILES,
  nexusConfig,
  nexusDir,
  SIDECAR_FILENAME
} from './paths'

type Json = Record<string, unknown>
type Fallback = 'id' | 'title'

const ACCENT_COLOR_SET = new Set<string>(ACCENT_COLORS)

// ---------- low-level helpers ----------

const AREA_COLOR_SET = new Set<AreaColor>(AREA_COLORS)

async function listEntries(dir: string): Promise<import('node:fs').Dirent[]> {
  try {
    return await readdir(dir, { withFileTypes: true })
  } catch {
    return []
  }
}

/** Lenient frontmatter split — mirrors AtomicYAMLMarkdown read semantics. */
export function splitFrontmatter(content: string): Json {
  if (!content.startsWith('---')) return {}
  const m = content.match(/^---\r?\n([\s\S]*?)\r?\n---/)
  if (!m) return {} // opening fence with no close -> treat whole file as body
  try {
    const parsed = parseYaml(m[1])
    return parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed)
      ? (parsed as Json)
      : {}
  } catch {
    return {} // malformed YAML -> still a valid page, empty frontmatter
  }
}

// ---------- page reads ----------

async function readPage(absFile: string, relFile: string): Promise<PageNode> {
  const fm = splitFrontmatter(await readFile(absFile, 'utf8'))
  return {
    kind: 'page',
    id: asString(fm.id) ?? adoptedId(relFile),
    title: basenameNoMd(basename(absFile)),
    icon: asString(fm.icon),
    path: relFile
  }
}

/** `.md` files directly in `absDir` (skips `_`-prefixed). */
async function readDirectPages(absDir: string, relDir: string): Promise<PageNode[]> {
  const out: PageNode[] = []
  for (const e of await listEntries(absDir)) {
    if (!e.isFile() || e.name.startsWith('_')) continue
    if (!e.name.toLowerCase().endsWith('.md')) continue
    const rel = relDir ? `${relDir}/${e.name}` : e.name
    try {
      out.push(await readPage(join(absDir, e.name), rel))
    } catch {
      /* unreadable page -> skip gracefully */
    }
  }
  return out
}

// ---------- LEGACY 3-tier reads (produce `vaults` during the migration window; deleted
//            in the contract step once index/CRUD/renderer consume `collections`) ----------

/** Roll-up: `.md` in `absDir` plus all non-excluded sub-folders (depth-cap spillover). */
async function collectMdDeep(absDir: string, relDir: string, excluded: string[]): Promise<PageNode[]> {
  let pages = await readDirectPages(absDir, relDir)
  for (const e of await listEntries(absDir)) {
    if (!e.isDirectory()) continue
    const rel = relDir ? `${relDir}/${e.name}` : e.name
    if (shouldSkipDir(e.name, rel, excluded)) continue
    pages = pages.concat(await collectMdDeep(join(absDir, e.name), rel, excluded))
  }
  return pages
}

async function legacyReadSet(
  absDir: string,
  relDir: string,
  name: string,
  sidecarMode: boolean,
  excluded: string[],
  fb: Fallback
): Promise<SetNode> {
  const meta = sidecarMode ? ((await readJsonObject(join(absDir, SIDECAR_FILENAME.set))) ?? {}) : {}
  const pages = await collectMdDeep(absDir, relDir, excluded)
  return {
    kind: 'set',
    selectable: false,
    id: asString(meta.id) ?? adoptedId(relDir),
    title: name,
    icon: asString(meta.icon),
    path: relDir,
    pages: resolveOrder(pages, asStringArray(meta.page_order), fb)
  }
}

async function legacyReadCollection(
  absDir: string,
  relDir: string,
  name: string,
  sidecarMode: boolean,
  excluded: string[],
  fb: Fallback
): Promise<CollectionNode> {
  const meta = sidecarMode
    ? ((await readJsonObject(join(absDir, SIDECAR_FILENAME.collection))) ?? {})
    : {}
  const sets: SetNode[] = []
  const rollup: { abs: string; rel: string }[] = []
  for (const e of await listEntries(absDir)) {
    if (!e.isDirectory()) continue
    const rel = `${relDir}/${e.name}`
    if (shouldSkipDir(e.name, rel, excluded)) continue
    const isSet = sidecarMode ? await pathExists(join(absDir, e.name, SIDECAR_FILENAME.set)) : true
    if (isSet) sets.push(await legacyReadSet(join(absDir, e.name), rel, e.name, sidecarMode, excluded, fb))
    else rollup.push({ abs: join(absDir, e.name), rel })
  }
  let pages = await readDirectPages(absDir, relDir)
  for (const r of rollup) pages = pages.concat(await collectMdDeep(r.abs, r.rel, excluded))
  return {
    kind: 'collection',
    id: asString(meta.id) ?? adoptedId(relDir),
    title: name,
    icon: asString(meta.icon),
    path: relDir,
    banner: asString(meta.banner),
    sets: resolveOrder(sets, asStringArray(meta.set_order), fb),
    pages: resolveOrder(pages, asStringArray(meta.page_order), fb)
  }
}

async function legacyReadPageType(
  absDir: string,
  relDir: string,
  name: string,
  sidecarMode: boolean,
  excluded: string[],
  fb: Fallback
): Promise<PageTypeNode> {
  const meta = sidecarMode
    ? ((await readJsonObject(join(absDir, SIDECAR_FILENAME.pageType))) ?? {})
    : {}
  const collections: CollectionNode[] = []
  const rollup: { abs: string; rel: string }[] = []
  for (const e of await listEntries(absDir)) {
    if (!e.isDirectory()) continue
    const rel = `${relDir}/${e.name}`
    if (shouldSkipDir(e.name, rel, excluded)) continue
    const isCollection = sidecarMode
      ? await pathExists(join(absDir, e.name, SIDECAR_FILENAME.collection))
      : true
    if (isCollection)
      collections.push(await legacyReadCollection(join(absDir, e.name), rel, e.name, sidecarMode, excluded, fb))
    else rollup.push({ abs: join(absDir, e.name), rel })
  }
  let pages = await readDirectPages(absDir, relDir)
  for (const r of rollup) pages = pages.concat(await collectMdDeep(r.abs, r.rel, excluded))
  return {
    kind: 'pageType',
    id: asString(meta.id) ?? adoptedId(relDir),
    title: name,
    icon: asString(meta.icon),
    path: relDir,
    banner: asString(meta.banner),
    collections: resolveOrder(collections, asStringArray(meta.collection_order), fb),
    pages: resolveOrder(pages, asStringArray(meta.page_order), fb)
  }
}

// ---------- container reads (2-tier: Collection -> recursive Set) ----------

/** Every non-excluded subfolder of a Collection or Set is itself a Set (position-driven,
 *  any depth). Shared by the Collection root and every Set level — the recursion. */
async function readChildSets(
  absDir: string,
  relDir: string,
  sidecarMode: boolean,
  excluded: string[],
  fb: Fallback
): Promise<SetNode[]> {
  const sets: SetNode[] = []
  for (const e of await listEntries(absDir)) {
    if (!e.isDirectory()) continue
    const rel = `${relDir}/${e.name}`
    if (shouldSkipDir(e.name, rel, excluded)) continue
    sets.push(await readSet(join(absDir, e.name), rel, e.name, sidecarMode, excluded, fb))
  }
  return sets
}

async function readSet(
  absDir: string,
  relDir: string,
  name: string,
  sidecarMode: boolean,
  excluded: string[],
  fb: Fallback
): Promise<SetNode> {
  const meta = sidecarMode ? ((await readJsonObject(join(absDir, SIDECAR_FILENAME.set))) ?? {}) : {}
  const sets = await readChildSets(absDir, relDir, sidecarMode, excluded, fb)
  const pages = await readDirectPages(absDir, relDir)
  return {
    kind: 'set',
    selectable: false,
    id: asString(meta.id) ?? adoptedId(relDir),
    title: name,
    icon: asString(meta.icon),
    path: relDir,
    banner: asString(meta.banner),
    sets: resolveOrder(sets, asStringArray(meta.set_order), fb),
    pages: resolveOrder(pages, asStringArray(meta.page_order), fb)
  }
}

async function readPageCollection(
  absDir: string,
  relDir: string,
  name: string,
  sidecarMode: boolean,
  excluded: string[],
  fb: Fallback
): Promise<CollectionNode> {
  const meta = sidecarMode
    ? ((await readJsonObject(join(absDir, SIDECAR_FILENAME.collection))) ?? {})
    : {}
  const sets = await readChildSets(absDir, relDir, sidecarMode, excluded, fb)
  const pages = await readDirectPages(absDir, relDir)
  return {
    kind: 'collection',
    id: asString(meta.id) ?? adoptedId(relDir),
    title: name,
    icon: asString(meta.icon),
    path: relDir,
    banner: asString(meta.banner),
    properties: Array.isArray(meta.properties)
      ? (meta.properties as CollectionNode['properties'])
      : undefined,
    sets: resolveOrder(sets, asStringArray(meta.set_order), fb),
    pages: resolveOrder(pages, asStringArray(meta.page_order), fb)
  }
}

// ---------- contexts ----------

async function readTier<T extends AreaNode | TopicNode | ProjectNode>(
  root: string,
  tier: 'areas' | 'topics' | 'projects',
  kind: T['kind'],
  sidecarMode: boolean,
  excluded: string[],
  order: string[] | undefined,
  fb: Fallback
): Promise<T[]> {
  const dir = contextTierDir(root, tier)
  const sidecar = SIDECAR_FILENAME[kind]
  const nodes: T[] = []
  for (const e of await listEntries(dir)) {
    if (!e.isDirectory()) continue
    if (shouldSkipDir(e.name, e.name, excluded)) continue
    const sc = await readJsonObject(join(dir, e.name, sidecar))
    if (sidecarMode && !sc) continue // tier entry must carry its sidecar
    const node = {
      kind,
      id: asString(sc?.id) ?? adoptedId(`${tier}/${e.name}`),
      title: e.name,
      icon: asString(sc?.icon),
      // Contexts live under .nexus/<tier>/ — the real on-disk path a mutation resolves
      // (distinct from the adoptedId seed above, which is layout-agnostic by design).
      path: `.nexus/${tier}/${e.name}`,
      banner: asString(sc?.banner)
    } as T
    if (kind === 'area') {
      const c = sc?.color
      ;(node as AreaNode).color =
        typeof c === 'string' && AREA_COLOR_SET.has(c as AreaColor) ? (c as AreaColor) : undefined
    }
    nodes.push(node)
  }
  return resolveOrder(nodes, order, fb)
}

// ---------- top level ----------

export async function readNexus(root: string): Promise<NexusTree> {
  if (!(await pathExists(root))) throw new Error(`Nexus root not found: ${root}`)

  const identity = await readJsonObject(nexusConfig(root, NEXUS_CONFIG_FILES.identity))
  const sidecarMode = !!asString(identity?.id)
  const id = sidecarMode ? (identity!.id as string) : adoptedId(root)
  const fb: Fallback = sidecarMode ? 'id' : 'title'
  // Nexus name = root folder basename (filename = title); description is the user-set blurb.
  const description = asString(identity?.description) ?? ''
  // The saved photo is always PNG (the crop exports image/png to .nexus/photo.png).
  const photoFile = asString(identity?.photo)
  let photo: string | null = null
  if (photoFile) {
    try {
      const buf = await readFile(join(nexusDir(root), photoFile))
      photo = `data:image/png;base64,${buf.toString('base64')}`
    } catch {
      photo = null
    }
  }

  const settings = (await readJsonObject(nexusConfig(root, NEXUS_CONFIG_FILES.settings))) ?? {}
  const excluded = asStringArray(settings.excluded_folders) ?? []
  const userLabels =
    settings.labels && typeof settings.labels === 'object' && !Array.isArray(settings.labels)
      ? (settings.labels as Record<string, string>)
      : {}
  const labels = { ...DEFAULT_LABELS, ...userLabels }
  const accentRaw = asString(settings.accent)
  const accent: AccentSetting =
    accentRaw === 'system' || (accentRaw != null && ACCENT_COLOR_SET.has(accentRaw))
      ? (accentRaw as AccentSetting)
      : DEFAULT_ACCENT
  const state = (await readJsonObject(nexusConfig(root, NEXUS_CONFIG_FILES.state))) ?? {}
  const savedConfig = (await readJsonObject(nexusConfig(root, NEXUS_CONFIG_FILES.savedConfig))) ?? {}
  const sectionsConfig = (await readJsonObject(nexusConfig(root, NEXUS_CONFIG_FILES.sidebarSections))) ?? {}
  const homepageConfig = (await readJsonObject(nexusConfig(root, NEXUS_CONFIG_FILES.homepage))) ?? {}

  // Saved strip — 3 fixed, code-keyed rows (inert in Phase 1).
  const savedLabels = (savedConfig.labels as Record<string, string>) ?? {}
  const saved: SavedNode[] = (
    [
      { key: 'homepage', title: 'Homepage', icon: 'house' },
      { key: 'calendar', title: 'Calendar', icon: 'calendar' },
      { key: 'recents', title: 'Recents', icon: 'clock' }
    ] as const
  ).map((s) => ({
    kind: 'saved',
    id: `saved-${s.key}`,
    key: s.key,
    title: savedLabels[s.key] ?? s.title,
    icon: s.icon
  }))

  // Contexts (sidecar mode only; absent for raw folders like ~/test).
  const contexts = {
    projects: await readTier<ProjectNode>(root, 'projects', 'project', sidecarMode, excluded, asStringArray(state.project_order), fb),
    topics: await readTier<TopicNode>(root, 'topics', 'topic', sidecarMode, excluded, asStringArray(state.topic_order), fb),
    areas: await readTier<AreaNode>(root, 'areas', 'area', sidecarMode, excluded, asStringArray(state.area_order), fb)
  }

  // Top-level containers, built side by side during the migration window: legacy 3-tier
  // `vaults` (gated by `_pagetype.json`; raw/structure mode produces none) and the new
  // 2-tier `collections` (gated by `_pagecollection.json`; raw mode treats every root
  // folder as a Collection). A given nexus is in exactly one format, so only one list
  // populates. Agenda singletons are discovered but NOT surfaced.
  const allTypes: PageTypeNode[] = []
  const allCollections: CollectionNode[] = []
  for (const e of await listEntries(root)) {
    if (!e.isDirectory()) continue
    if (shouldSkipDir(e.name, e.name, excluded)) continue
    const abs = join(root, e.name)
    const hasAgendaSidecar =
      (await pathExists(join(abs, SIDECAR_FILENAME.taskConfig))) ||
      (await pathExists(join(abs, SIDECAR_FILENAME.eventConfig)))
    if (hasAgendaSidecar) continue
    const isPageType = sidecarMode ? await pathExists(join(abs, SIDECAR_FILENAME.pageType)) : false
    const isCollection = sidecarMode ? await pathExists(join(abs, SIDECAR_FILENAME.collection)) : true
    if (AGENDA_FOLDER_NAMES.has(e.name) && !(sidecarMode && (isPageType || isCollection))) continue
    if (isCollection) allCollections.push(await readPageCollection(abs, e.name, e.name, sidecarMode, excluded, fb))
    else if (isPageType) allTypes.push(await legacyReadPageType(abs, e.name, e.name, sidecarMode, excluded, fb))
  }
  const orderedTypes = resolveOrder(allTypes, asStringArray(state.vault_order), fb)
  const collectionOrder = asStringArray(state.collection_order) ?? asStringArray(state.vault_order)
  const orderedCollections = resolveOrder(allCollections, collectionOrder, fb)

  // Partition into user sections vs ungrouped. (sidebar-sections keys by `collectionIDs`,
  // falling back to the legacy `vaultIDs` for the migration window.)
  const rawSections =
    (sectionsConfig.sections as {
      id: string
      label: string
      collectionIDs?: string[]
      vaultIDs?: string[]
    }[]) ?? []
  const claimedV = new Set<string>()
  const claimedC = new Set<string>()
  const userSections: UserSection[] = rawSections.map((s) => {
    const vaults = (s.vaultIDs ?? [])
      .map((id) => orderedTypes.find((t) => t.id === id))
      .filter((t): t is PageTypeNode => !!t)
    const collections = (s.collectionIDs ?? s.vaultIDs ?? [])
      .map((id) => orderedCollections.find((c) => c.id === id))
      .filter((c): c is CollectionNode => !!c)
    vaults.forEach((v) => claimedV.add(v.id))
    collections.forEach((c) => claimedC.add(c.id))
    return { id: s.id, label: s.label, vaults, collections }
  })
  const vaults = orderedTypes.filter((t) => !claimedV.has(t.id))
  const collections = orderedCollections.filter((c) => !claimedC.has(c.id))

  return {
    nexus: { id, rootPath: root, name: basename(root), description, photo },
    homepage: { banner: asString(homepageConfig.banner) },
    saved,
    contexts,
    vaults,
    collections,
    userSections,
    labels,
    accent
  }
}
