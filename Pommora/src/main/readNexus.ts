// The whole read engine: one recursive, read-only walk of a nexus root.
// Supports BOTH the sidecar-driven path (`.nexus/` + per-folder sidecars) and
// the structure-classification path (raw/un-adopted folders, e.g. ~/test).
// No file is ever opened for writing.

import { readdir, readFile } from 'node:fs/promises'
import { basename, join } from 'node:path'
import { parse as parseYaml } from 'yaml'
import type {
  AccentColor,
  AccentSetting,
  AreaColor,
  AreaNode,
  CollectionNode,
  LabelPair,
  NexusLabels,
  NexusTree,
  PageNode,
  ProjectNode,
  SavedNode,
  SetNode,
  ConnectionColorSetting,
  EntityIconKind,
  FolderPlacement,
  Personalization,
  SidebarMode,
  TopicNode,
  UserSection
} from '@shared/types'
import {
  ACCENT_COLORS,
  AREA_COLORS,
  DEFAULT_ACCENT,
  DEFAULT_COMMANDS,
  DEFAULT_LABELS,
  DEFAULT_TIME_FORMAT,
  ENTITY_ICON_KINDS,
  coerceViewScale
} from '@shared/types'
import { savedView, type SavedView } from '@shared/views'
import { coerceOpenIn, coerceViewButton, coerceViewStyle } from '@shared/schemas'
import type { PropertyDefinition } from '@shared/properties'
import { adoptedId } from './ids'
import { pathExists, readJsonObject } from './io/atomicWrite'
import { orderedDefs, readRegistry, type PropertyRegistry } from './io/propertiesRegistry'
import { asString, asStringArray, basenameNoMd } from './coerce'
import { shouldSkipDir } from './exclusion'
import { resolveOrder } from './order'
import { beginWalk, cachedParse, endWalk } from './walkCache'
import {
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

// Swift `accent_color` values that aren't in React's own palette → nearest React token.
// React's own values (including the 6 that overlap Swift) pass through unchanged; React
// keeps its own accent vocabulary, this only maps Swift's extras on read.
const SWIFT_ONLY_ACCENT: Record<string, AccentColor> = { pink: 'purple', gray: 'grey' }

function resolveAccent(raw: string | undefined): AccentSetting {
  if (raw === 'system') return 'system'
  if (raw != null && ACCENT_COLOR_SET.has(raw)) return raw as AccentColor
  if (raw != null && raw in SWIFT_ONLY_ACCENT) return SWIFT_ONLY_ACCENT[raw]
  return DEFAULT_ACCENT
}

// Coerce the on-disk `settings.personalization` blob into a validated Personalization, per-field
// (absent/invalid → undefined = the built-in default). Accent is resolved separately into
// tree.accent (back-compat with the legacy top-level accent_color), so it isn't surfaced here.
export function readPersonalization(raw: unknown): Personalization {
  const p = raw != null && typeof raw === 'object' && !Array.isArray(raw) ? (raw as Record<string, unknown>) : {}
  const bool = (v: unknown): boolean | undefined => (typeof v === 'boolean' ? v : undefined)
  const placement = (v: unknown): FolderPlacement | undefined => (v === 'top' || v === 'bottom' ? v : undefined)
  const mode = (v: unknown): SidebarMode | undefined =>
    v === 'collections' || v === 'contexts' || v === 'agenda' ? v : undefined
  const ribbonOrder = Array.isArray(p.ribbonOrder)
    ? p.ribbonOrder.filter((v): v is string => typeof v === 'string' && v.length > 0)
    : []
  const conn = asString(p.connectionColor)
  const rawIcons =
    p.defaultIcons != null && typeof p.defaultIcons === 'object' && !Array.isArray(p.defaultIcons)
      ? (p.defaultIcons as Record<string, unknown>)
      : {}
  const defaultIcons: Partial<Record<EntityIconKind, string>> = {}
  for (const k of ENTITY_ICON_KINDS) {
    const v = asString(rawIcons[k])
    if (v) defaultIcons[k] = v
  }
  const favoriteIcons = Array.isArray(p.favoriteIcons)
    ? p.favoriteIcons.filter((v): v is string => typeof v === 'string' && v.length > 0)
    : []
  return {
    connectionColor:
      conn === 'accent' || (conn != null && ACCENT_COLOR_SET.has(conn)) ? (conn as ConnectionColorSetting) : undefined,
    hideChevrons: bool(p.hideChevrons),
    outlinerLines: bool(p.outlinerLines),
    defaultIcons: Object.keys(defaultIcons).length ? defaultIcons : undefined,
    favoriteIcons: favoriteIcons.length ? favoriteIcons : undefined,
    setPlacement: placement(p.setPlacement),
    subSetPlacement: placement(p.subSetPlacement),
    sidebarMode: mode(p.sidebarMode),
    ribbonOrder: ribbonOrder.length ? ribbonOrder : undefined,
    defaultViewScale: coerceViewScale(p.defaultViewScale)
  }
}

// Overlay the on-disk `settings.commands` map onto DEFAULT_COMMANDS — string values only, so a
// malformed entry falls back to the built-in binding instead of poisoning the map.
export function readCommands(raw: unknown): Record<string, string> {
  const commands = { ...DEFAULT_COMMANDS }
  const c = raw != null && typeof raw === 'object' && !Array.isArray(raw) ? (raw as Record<string, unknown>) : {}
  for (const [key, value] of Object.entries(c)) {
    if (typeof value === 'string' && value.length > 0) commands[key] = value
  }
  return commands
}

// Parse Swift's nested snake_case `settings.labels` into the structured camelCase
// NexusLabels, defaulting per-field so a partial/absent blob still yields full labels.
function readLabels(raw: unknown): NexusLabels {
  const obj = (v: unknown): Record<string, unknown> =>
    v != null && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {}
  const pair = (v: unknown, fallback: LabelPair): LabelPair => {
    const o = obj(v)
    return { singular: asString(o.singular) ?? fallback.singular, plural: asString(o.plural) ?? fallback.plural }
  }
  const L = obj(raw)
  // Migrate a legacy `sidebar_sections.{areas,topics}` blob into the area/topic tier plurals when the
  // new LabelPairs are absent (singular defaults). The old `pages` header is dropped — the Collections
  // sidebar header now derives from pageCollection.plural.
  const ss = obj(L.sidebar_sections)
  const tier = (key: string, legacyPlural: unknown, fallback: LabelPair): LabelPair =>
    pair(L[key], { singular: fallback.singular, plural: asString(legacyPlural) ?? fallback.plural })
  return {
    area: tier('area', ss.areas, DEFAULT_LABELS.area),
    topic: tier('topic', ss.topics, DEFAULT_LABELS.topic),
    project: pair(L.project, DEFAULT_LABELS.project),
    pageCollection: pair(L.page_collection, DEFAULT_LABELS.pageCollection),
    pageSet: pair(L.page_set, DEFAULT_LABELS.pageSet),
    agendaTask: pair(L.agenda_task, DEFAULT_LABELS.agendaTask),
    agendaEvent: pair(L.agenda_event, DEFAULT_LABELS.agendaEvent)
  }
}

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

/** Per-folder sidecar JSON, served through the walk cache — parsed once per (mtime, size). */
const readSidecar = (absPath: string): Promise<Json | null> =>
  cachedParse(absPath, () => readJsonObject(absPath))

// ---------- page reads ----------

async function readPage(absFile: string, relFile: string): Promise<PageNode> {
  return cachedParse(absFile, async () => {
    const fm = splitFrontmatter(await readFile(absFile, 'utf8'))
    return {
      kind: 'page',
      id: asString(fm.id) ?? adoptedId(relFile),
      title: basenameNoMd(basename(absFile)),
      icon: asString(fm.icon),
      path: relFile
    }
  })
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

// ---------- container reads (2-tier: Collection -> recursive Set) ----------

/** Lenient read of a sidecar `views[]` — drops any view that fails to decode rather than
 *  poisoning the whole container read; absent/empty ⇒ undefined. */
function parseViews(raw: unknown): SavedView[] | undefined {
  if (!Array.isArray(raw)) return undefined
  const out: SavedView[] = []
  for (const v of raw) {
    const r = savedView.safeParse(v)
    if (r.success) out.push(r.data)
  }
  return out.length > 0 ? out : undefined
}

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
  const meta = sidecarMode ? ((await readSidecar(join(absDir, SIDECAR_FILENAME.set))) ?? {}) : {}
  const sets = await readChildSets(absDir, relDir, sidecarMode, excluded, fb)
  const pages = await readDirectPages(absDir, relDir)
  return {
    kind: 'set',
    id: asString(meta.id) ?? adoptedId(relDir),
    title: name,
    icon: asString(meta.icon),
    path: relDir,
    banner: asString(meta.banner),
    sets: resolveOrder(sets, asStringArray(meta.set_order), fb),
    pages: resolveOrder(pages, asStringArray(meta.page_order), fb),
    views: parseViews(meta.views),
    viewButton: coerceViewButton(meta.view_button),
    viewStyle: coerceViewStyle(meta.view_style)
  }
}

/** effectiveSchema(C): assignment ids → their registry defs, in order; drops dangling refs
 *  (a def deleted but an assignment not yet reconciled must not become an undefined hole). */
export function resolveAssignedSchema(
  ids: unknown,
  registry: PropertyRegistry
): PropertyDefinition[] | undefined {
  if (!Array.isArray(ids)) return undefined
  const defs = ids
    .filter((id): id is string => typeof id === 'string')
    .map((id) => registry[id])
    .filter((d): d is PropertyDefinition => Boolean(d))
  return defs.length ? defs : undefined
}

async function readPageCollection(
  absDir: string,
  relDir: string,
  name: string,
  sidecarMode: boolean,
  excluded: string[],
  fb: Fallback,
  registry: PropertyRegistry
): Promise<CollectionNode> {
  const meta = sidecarMode
    ? ((await readSidecar(join(absDir, SIDECAR_FILENAME.collection))) ?? {})
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
    properties: resolveAssignedSchema(meta.properties, registry),
    sets: resolveOrder(sets, asStringArray(meta.set_order), fb),
    pages: resolveOrder(pages, asStringArray(meta.page_order), fb),
    views: parseViews(meta.views),
    openIn: coerceOpenIn(meta.open_in),
    viewButton: coerceViewButton(meta.view_button),
    viewStyle: coerceViewStyle(meta.view_style)
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
    const sc = await readSidecar(join(dir, e.name, sidecar))
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
  beginWalk(root)
  try {
    return await walkNexus(root)
  } finally {
    endWalk()
  }
}

async function walkNexus(root: string): Promise<NexusTree> {
  const identity = await readJsonObject(nexusConfig(root, NEXUS_CONFIG_FILES.identity))
  const sidecarMode = !!asString(identity?.id)
  const id = sidecarMode ? (identity!.id as string) : adoptedId(root)
  const fb: Fallback = sidecarMode ? 'id' : 'title'

  const settings = (await readJsonObject(nexusConfig(root, NEXUS_CONFIG_FILES.settings))) ?? {}
  const excluded = asStringArray(settings.excluded_folders) ?? []
  const labels = readLabels(settings.labels)
  const rawPersonalization =
    settings.personalization != null &&
    typeof settings.personalization === 'object' &&
    !Array.isArray(settings.personalization)
      ? (settings.personalization as Record<string, unknown>)
      : {}
  // Accent's new home is personalization.accent; the legacy top-level accent_color is the back-compat
  // fallback for un-migrated nexuses (G-4). resolveAccent normalizes either into an AccentSetting.
  const accent = resolveAccent(asString(rawPersonalization.accent) ?? asString(settings.accent_color))
  const personalization = readPersonalization(rawPersonalization)
  const commands = readCommands(settings.commands)
  const timeFormat = settings.time_format === 'twentyFourHour' ? 'twentyFourHour' : DEFAULT_TIME_FORMAT
  // Profile image + subtitle live in settings (Swift parity), not nexus.json. profileImage is a
  // nexus-relative asset path the renderer serves via nexus-asset://; subtitle is plain text.
  const profileImage = asString(settings.profile_image) ?? null
  const profileSubtitle = asString(settings.profile_subtitle) ?? ''
  const state = (await readJsonObject(nexusConfig(root, NEXUS_CONFIG_FILES.state))) ?? {}
  const savedConfig = (await readJsonObject(nexusConfig(root, NEXUS_CONFIG_FILES.savedConfig))) ?? {}
  const sectionsConfig = (await readJsonObject(nexusConfig(root, NEXUS_CONFIG_FILES.sidebarSections))) ?? {}
  const homepageConfig = (await readJsonObject(nexusConfig(root, NEXUS_CONFIG_FILES.homepage))) ?? {}
  const registry = await readRegistry(root)

  // Saved strip — 3 fixed, code-keyed rows; labels come from saved-config `items[{key,label}]`.
  const savedItems = Array.isArray(savedConfig.items)
    ? (savedConfig.items as { key?: unknown; label?: unknown }[])
    : []
  const savedLabelByKey = new Map<string, string>()
  for (const it of savedItems) {
    const k = asString(it?.key)
    const l = asString(it?.label)
    if (k && l) savedLabelByKey.set(k, l)
  }
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
    title: savedLabelByKey.get(s.key) ?? s.title,
    icon: s.icon
  }))

  // Contexts (sidecar mode only; absent for raw folders like ~/test).
  const contexts = {
    projects: await readTier<ProjectNode>(root, 'projects', 'project', sidecarMode, excluded, asStringArray(state.project_order), fb),
    topics: await readTier<TopicNode>(root, 'topics', 'topic', sidecarMode, excluded, asStringArray(state.topic_order), fb),
    areas: await readTier<AreaNode>(root, 'areas', 'area', sidecarMode, excluded, asStringArray(state.area_order), fb)
  }

  // Top-level Collections (gated by `_pagecollection.json`; raw mode treats every root folder
  // as a Collection). Agenda singletons are identified ONLY by their config sidecar
  // (`_taskconfig`/`_eventconfig`) — never by folder name — and are not surfaced as Collections.
  const allCollections: CollectionNode[] = []
  for (const e of await listEntries(root)) {
    if (!e.isDirectory()) continue
    if (shouldSkipDir(e.name, e.name, excluded)) continue
    const abs = join(root, e.name)
    const hasAgendaSidecar =
      (await pathExists(join(abs, SIDECAR_FILENAME.taskConfig))) ||
      (await pathExists(join(abs, SIDECAR_FILENAME.eventConfig)))
    if (hasAgendaSidecar) continue
    const isCollection = sidecarMode ? await pathExists(join(abs, SIDECAR_FILENAME.collection)) : true
    if (isCollection) allCollections.push(await readPageCollection(abs, e.name, e.name, sidecarMode, excluded, fb, registry.defs))
  }
  const orderedCollections = resolveOrder(allCollections, asStringArray(state.collection_order), fb)

  // Partition into user sections vs ungrouped (sidebar-sections keys by `collectionIDs`).
  const rawSections = (sectionsConfig.sections as { id: string; label: string; collectionIDs?: string[] }[]) ?? []
  const claimed = new Set<string>()
  const userSections: UserSection[] = rawSections.map((s) => {
    const collections = (s.collectionIDs ?? [])
      .map((id) => orderedCollections.find((c) => c.id === id))
      .filter((c): c is CollectionNode => !!c)
    collections.forEach((c) => claimed.add(c.id))
    return { id: s.id, label: s.label, collections }
  })
  const collections = orderedCollections.filter((c) => !claimed.has(c.id))

  return {
    nexus: { id, rootPath: root, name: basename(root), profileImage, profileSubtitle },
    homepage: { banner: asString(homepageConfig.banner), locked: homepageConfig.blocks_locked === true },
    saved,
    contexts,
    collections,
    userSections,
    labels,
    accent,
    timeFormat,
    personalization,
    commands,
    registry: orderedDefs(registry)
  }
}
