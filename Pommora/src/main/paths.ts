// Pure path module — the one place that knows the on-disk layout.
// Mirrors the Swift NexusPaths. node:path only; no fs.

import { join } from 'node:path'

export type ContextTier = 'areas' | 'topics' | 'projects'

export type SidecarKind =
  | 'area'
  | 'topic'
  | 'project'
  | 'collection'
  | 'set'
  | 'taskConfig'
  | 'eventConfig'

/** Per-kind sidecar filenames (the kind authority on disk). */
export const SIDECAR_FILENAME: Record<SidecarKind, string> = {
  area: '_area.json',
  topic: '_topic.json',
  project: '_project.json',
  collection: '_pagecollection.json',
  set: '_pageset.json',
  taskConfig: '_taskconfig.json',
  eventConfig: '_eventconfig.json'
}

export function nexusDir(root: string): string {
  return join(root, '.nexus')
}

export function nexusConfig(root: string, file: string): string {
  return join(nexusDir(root), file)
}

export function contextTierDir(root: string, tier: ContextTier): string {
  return join(nexusDir(root), tier)
}

/** The homepage block host's content folder — its markdown-block `.md` files live here
 *  (distinct from the `homepage.json` config file). Real hosts use their own folders. */
export const HOMEPAGE_HOST_DIRNAME = 'homepage'

export function blockHostDir(root: string, _host: { kind: 'homepage' }): string {
  return join(nexusDir(root), HOMEPAGE_HOST_DIRNAME)
}

export const NEXUS_CONFIG_FILES = {
  identity: 'nexus.json',
  settings: 'settings.json',
  state: 'state.json',
  homepage: 'homepage.json',
  savedConfig: 'saved-config.json',
  sidebarSections: 'sidebar-sections.json',
  folds: 'folds.json',
  tableHeadingColumns: 'tableHeadingColumns.json',
  activeViews: 'activeViews.json',
  viewOrders: 'viewOrders.json',
  properties: 'properties.json',
  linkTitles: 'linkTitles.json',
  navRecents: 'navRecents.json',
  navFavorites: 'navFavorites.json'
} as const

/** The `.nexus/` files that are per-machine display state or a regeneratable accelerator, never
 *  shared — the set to exclude from any device-to-device sync (heading folds, active view, per-view
 *  row order, table-heading toggles, the fetched-page-title cache). Everything else under `.nexus/`
 *  (registry, Contexts, Homepage, settings, assets) is canonical. */
export const DEVICE_LOCAL_NEXUS_FILES: ReadonlySet<string> = new Set([
  NEXUS_CONFIG_FILES.folds,
  NEXUS_CONFIG_FILES.activeViews,
  NEXUS_CONFIG_FILES.viewOrders,
  NEXUS_CONFIG_FILES.tableHeadingColumns,
  NEXUS_CONFIG_FILES.linkTitles
])
