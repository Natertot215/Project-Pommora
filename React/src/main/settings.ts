// Per-Nexus settings (`.nexus/settings.json`), Swift-compatible. Swift's decoder REQUIRES
// `version` + `labels` + `modified_at`, so a partial settings.json (e.g. one React wrote with
// only profile_image) makes Swift reseed and lose data. ensureSettings guarantees the file is
// always a full, Swift-decodable shape — the settings half of opening the same folder in either
// app with no conflict (the identity half is ensureIdentity).

import { mkdir } from 'node:fs/promises'
import { DEFAULT_LABELS, type NexusLabels, type SubfieldConfig } from '@shared/types'
import { readJsonObject, writeJson } from './io/atomicWrite'
import { swiftISODate } from './identity'
import { nexusDir, nexusConfig, NEXUS_CONFIG_FILES } from './paths'

// Tracks Swift's `Settings.currentDefaultsVersion` — written so Swift's auto-migration sees a
// current file and is a no-op (no churn). If Swift later bumps it, Swift runs one harmless
// migration on first open and rewrites this value.
const SWIFT_DEFAULTS_VERSION = 6

/** React's structured (camelCase) labels → Swift's snake_case on-disk shape. */
function labelsToDisk(l: NexusLabels): Record<string, unknown> {
  return {
    sidebar_sections: { areas: l.sidebarSections.areas, topics: l.sidebarSections.topics, pages: l.sidebarSections.pages },
    page_collection: { singular: l.pageCollection.singular, plural: l.pageCollection.plural },
    page_set: { singular: l.pageSet.singular, plural: l.pageSet.plural },
    project: { singular: l.project.singular, plural: l.project.plural },
    agenda_task: { singular: l.agendaTask.singular, plural: l.agendaTask.plural },
    agenda_event: { singular: l.agendaEvent.singular, plural: l.agendaEvent.plural }
  }
}

/** A full, Swift-decodable settings seed. The default for any settings write so the file can
 *  never go partial, and the body of the absent-file branch in ensureSettings. */
export function defaultSettingsSeed(): Record<string, unknown> {
  return {
    version: 1,
    defaults_version: SWIFT_DEFAULTS_VERSION,
    labels: labelsToDisk(DEFAULT_LABELS),
    show_page_icon: false,
    excluded_folders: [],
    profile_subtitle: '',
    modified_at: swiftISODate()
  }
}

/** Ensure `.nexus/settings.json` is a full, Swift-decodable shape. Absent → write the seed.
 *  Present → backfill only the keys Swift's decoder REQUIRES (version, labels, modified_at) +
 *  defaults_version (avoids a migration rewrite) when missing; a complete file is left
 *  byte-identical (no churn). Foreign + user keys are always preserved. */
export async function ensureSettings(root: string): Promise<void> {
  const path = nexusConfig(root, NEXUS_CONFIG_FILES.settings)
  const existing = await readJsonObject(path)
  if (!existing) {
    await mkdir(nexusDir(root), { recursive: true })
    await writeJson(path, defaultSettingsSeed())
    return
  }
  const patch: Record<string, unknown> = {}
  if (typeof existing.version !== 'number') patch.version = 1
  if (typeof existing.defaults_version !== 'number') patch.defaults_version = SWIFT_DEFAULTS_VERSION
  if (!existing.labels || typeof existing.labels !== 'object') patch.labels = labelsToDisk(DEFAULT_LABELS)
  if (typeof existing.modified_at !== 'string') patch.modified_at = swiftISODate()
  if (Object.keys(patch).length > 0) await writeJson(path, { ...existing, ...patch })
}

/** Read the React-owned `subfield` foreign key from settings.json (null when absent/malformed). */
export async function readSubfield(root: string): Promise<SubfieldConfig | null> {
  const existing = await readJsonObject(nexusConfig(root, NEXUS_CONFIG_FILES.settings))
  const sub = existing?.subfield
  if (!sub || typeof sub !== 'object') return null
  const s = sub as Record<string, unknown>
  return {
    order: s.order && typeof s.order === 'object' ? (s.order as SubfieldConfig['order']) : {},
    expanded: typeof s.expanded === 'boolean' ? s.expanded : true
  }
}

/** Write the `subfield` key, preserving every other (Swift-required + foreign) key in settings.json. */
export async function writeSubfield(root: string, config: SubfieldConfig): Promise<void> {
  await ensureSettings(root)
  const path = nexusConfig(root, NEXUS_CONFIG_FILES.settings)
  const existing = (await readJsonObject(path)) ?? {}
  await writeJson(path, { ...existing, subfield: config })
}
