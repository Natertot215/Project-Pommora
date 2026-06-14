// The whole read engine: one recursive, read-only walk of a nexus root.
// Supports BOTH the sidecar-driven path (`.nexus/` + per-folder sidecars) and
// the structure-classification path (raw/un-adopted folders, e.g. ~/test).
// No file is ever opened for writing.

import { readdir, readFile, stat } from 'node:fs/promises'
import { basename, join } from 'node:path'
import { createHash } from 'node:crypto'
import { parse as parseYaml } from 'yaml'
import type {
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
import { DEFAULT_LABELS } from '@shared/types'
import { shouldSkipDir } from './exclusion'
import { resolveOrder } from './order'
import {
  AGENDA_FOLDER_NAMES,
  contextTierDir,
  NEXUS_CONFIG_FILES,
  nexusConfig,
  SIDECAR_FILENAME
} from './paths'

type Json = Record<string, unknown>
type Fallback = 'id' | 'title'

// ---------- low-level helpers ----------

async function readJson(p: string): Promise<Json | null> {
  try {
    const parsed = JSON.parse(await readFile(p, 'utf8'))
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? (parsed as Json) : null
  } catch {
    return null
  }
}

const AREA_COLORS = new Set<AreaColor>([
  'gray',
  'brown',
  'orange',
  'yellow',
  'green',
  'blue',
  'purple',
  'pink',
  'red',
  'accent'
])

async function pathExists(p: string): Promise<boolean> {
  try {
    await stat(p)
    return true
  } catch {
    return false
  }
}

async function listEntries(dir: string): Promise<import('node:fs').Dirent[]> {
  try {
    return await readdir(dir, { withFileTypes: true })
  } catch {
    return []
  }
}

function adoptedId(relPath: string): string {
  return 'adopted-' + createHash('sha256').update(relPath).digest('hex').slice(0, 16)
}

function basenameNoMd(name: string): string {
  return name.replace(/\.md$/i, '')
}

function asString(v: unknown): string | undefined {
  return typeof v === 'string' && v.length > 0 ? v : undefined
}

function asStringArray(v: unknown): string[] | undefined {
  return Array.isArray(v) && v.every((x) => typeof x === 'string') ? (v as string[]) : undefined
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
    icon: asString(fm.icon)
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

// ---------- container reads (pageType -> collection -> set) ----------

async function readSet(
  absDir: string,
  relDir: string,
  name: string,
  sidecarMode: boolean,
  excluded: string[],
  fb: Fallback
): Promise<SetNode> {
  const meta = sidecarMode ? ((await readJson(join(absDir, SIDECAR_FILENAME.set))) ?? {}) : {}
  // A set is the depth cap: its own .md + any deeper folders roll up.
  const pages = await collectMdDeep(absDir, relDir, excluded)
  return {
    kind: 'set',
    selectable: false,
    id: asString(meta.id) ?? adoptedId(relDir),
    title: name,
    icon: asString(meta.icon),
    pages: resolveOrder(pages, asStringArray(meta.page_order), fb)
  }
}

async function readCollection(
  absDir: string,
  relDir: string,
  name: string,
  sidecarMode: boolean,
  excluded: string[],
  fb: Fallback
): Promise<CollectionNode> {
  const meta = sidecarMode
    ? ((await readJson(join(absDir, SIDECAR_FILENAME.collection))) ?? {})
    : {}
  const sets: SetNode[] = []
  const rollup: { abs: string; rel: string }[] = []
  for (const e of await listEntries(absDir)) {
    if (!e.isDirectory()) continue
    const rel = `${relDir}/${e.name}`
    if (shouldSkipDir(e.name, rel, excluded)) continue
    const isSet = sidecarMode
      ? await pathExists(join(absDir, e.name, SIDECAR_FILENAME.set))
      : true
    if (isSet) sets.push(await readSet(join(absDir, e.name), rel, e.name, sidecarMode, excluded, fb))
    else rollup.push({ abs: join(absDir, e.name), rel })
  }
  let pages = await readDirectPages(absDir, relDir)
  for (const r of rollup) pages = pages.concat(await collectMdDeep(r.abs, r.rel, excluded))
  return {
    kind: 'collection',
    id: asString(meta.id) ?? adoptedId(relDir),
    title: name,
    icon: asString(meta.icon),
    sets: resolveOrder(sets, asStringArray(meta.set_order), fb),
    pages: resolveOrder(pages, asStringArray(meta.page_order), fb)
  }
}

async function readPageType(
  absDir: string,
  relDir: string,
  name: string,
  sidecarMode: boolean,
  excluded: string[],
  fb: Fallback
): Promise<PageTypeNode> {
  const meta = sidecarMode
    ? ((await readJson(join(absDir, SIDECAR_FILENAME.pageType))) ?? {})
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
      collections.push(await readCollection(join(absDir, e.name), rel, e.name, sidecarMode, excluded, fb))
    else rollup.push({ abs: join(absDir, e.name), rel })
  }
  let pages = await readDirectPages(absDir, relDir)
  for (const r of rollup) pages = pages.concat(await collectMdDeep(r.abs, r.rel, excluded))
  return {
    kind: 'pageType',
    id: asString(meta.id) ?? adoptedId(relDir),
    title: name,
    icon: asString(meta.icon),
    collections: resolveOrder(collections, asStringArray(meta.collection_order), fb),
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
    const sc = await readJson(join(dir, e.name, sidecar))
    if (sidecarMode && !sc) continue // tier entry must carry its sidecar
    const node = {
      kind,
      id: asString(sc?.id) ?? adoptedId(`${tier}/${e.name}`),
      title: e.name,
      icon: asString(sc?.icon)
    } as T
    if (kind === 'area') {
      const c = sc?.color
      ;(node as AreaNode).color =
        typeof c === 'string' && AREA_COLORS.has(c as AreaColor) ? (c as AreaColor) : undefined
    }
    nodes.push(node)
  }
  return resolveOrder(nodes, order, fb)
}

// ---------- top level ----------

export async function readNexus(root: string): Promise<NexusTree> {
  if (!(await pathExists(root))) throw new Error(`Nexus root not found: ${root}`)

  const identity = await readJson(nexusConfig(root, NEXUS_CONFIG_FILES.identity))
  const sidecarMode = !!asString(identity?.id)
  const id = sidecarMode ? (identity!.id as string) : adoptedId(root)
  const fb: Fallback = sidecarMode ? 'id' : 'title'

  const settings = (await readJson(nexusConfig(root, NEXUS_CONFIG_FILES.settings))) ?? {}
  const excluded = asStringArray(settings.excluded_folders) ?? []
  const userLabels =
    settings.labels && typeof settings.labels === 'object' && !Array.isArray(settings.labels)
      ? (settings.labels as Record<string, string>)
      : {}
  const labels = { ...DEFAULT_LABELS, ...userLabels }
  const state = (await readJson(nexusConfig(root, NEXUS_CONFIG_FILES.state))) ?? {}
  const savedConfig = (await readJson(nexusConfig(root, NEXUS_CONFIG_FILES.savedConfig))) ?? {}
  const sectionsConfig = (await readJson(nexusConfig(root, NEXUS_CONFIG_FILES.sidebarSections))) ?? {}

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

  // Vaults (flat at root). Agenda singletons are discovered but NOT surfaced.
  const allTypes: PageTypeNode[] = []
  for (const e of await listEntries(root)) {
    if (!e.isDirectory()) continue
    if (shouldSkipDir(e.name, e.name, excluded)) continue
    const hasAgendaSidecar =
      (await pathExists(join(root, e.name, SIDECAR_FILENAME.taskConfig))) ||
      (await pathExists(join(root, e.name, SIDECAR_FILENAME.eventConfig)))
    const isPageType = sidecarMode
      ? await pathExists(join(root, e.name, SIDECAR_FILENAME.pageType))
      : true
    // Agenda singletons are discovered but not surfaced. A task/event sidecar is
    // authoritative; the conventional name applies only when the folder isn't an
    // explicit PageType (so an adopted PageType named "Tasks" still surfaces).
    if (hasAgendaSidecar) continue
    if (AGENDA_FOLDER_NAMES.has(e.name) && !(sidecarMode && isPageType)) continue
    if (!isPageType) continue
    allTypes.push(await readPageType(join(root, e.name), e.name, e.name, sidecarMode, excluded, fb))
  }
  const orderedTypes = resolveOrder(allTypes, asStringArray(state.vault_order), fb)

  // Partition into user sections vs ungrouped.
  const rawSections = (sectionsConfig.sections as { id: string; label: string; vaultIDs?: string[] }[]) ?? []
  const claimed = new Set<string>()
  const userSections: UserSection[] = rawSections.map((s) => {
    const vaults = (s.vaultIDs ?? [])
      .map((vid) => orderedTypes.find((t) => t.id === vid))
      .filter((t): t is PageTypeNode => !!t)
    vaults.forEach((v) => claimed.add(v.id))
    return { id: s.id, label: s.label, vaults }
  })
  const vaults = orderedTypes.filter((t) => !claimed.has(t.id))

  return {
    nexus: { id, rootPath: root },
    saved,
    contexts,
    vaults,
    userSections,
    labels
  }
}
