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
  properties: 'properties.json'
} as const
