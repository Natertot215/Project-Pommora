// Open-time write-pass that stamps a real ULID into every entity still lacking a persisted
// id (raw folder → sidecar, externally-authored page → frontmatter id). Walks parents
// before children so a Set's healed parent_id points at the parent's fresh id. Idempotent;
// folder position decides kind — a root child is a Collection, anything nested is a Set.

import { readdir, readFile } from 'node:fs/promises'
import type { Dirent } from 'node:fs'
import { join } from 'node:path'
import { newId } from './ids'
import { atomicWriteFile, readJsonObject, pathExists } from './io/atomicWrite'
import { writeSidecar } from './sidecarIO'
import { splitEnvelope, mergeFrontmatter, readFrontmatterFields } from './io/pageFile'
import { asString, asStringArray } from './coerce'
import { shouldSkipDir } from './exclusion'
import { AGENDA_FOLDER_NAMES, NEXUS_CONFIG_FILES, SIDECAR_FILENAME, nexusConfig } from './paths'

type FolderKind = 'collection' | 'set'

async function listEntries(dir: string): Promise<Dirent[]> {
  try {
    return await readdir(dir, { withFileTypes: true })
  } catch {
    return []
  }
}

/** Stamp a single `.md` page that lacks an id. Returns whether it wrote. Foreign
 *  frontmatter + body survive via the preserving merge. */
async function stampPage(absFile: string): Promise<boolean> {
  const content = await readFile(absFile, 'utf8')
  if (asString(readFrontmatterFields(content).id)) return false // already adopted
  const { body } = splitEnvelope(content)
  await atomicWriteFile(absFile, mergeFrontmatter(content, { id: newId() }, ['id'], body))
  return true
}

/** Resolve a folder's id, minting + persisting one when it has none. A Set heals its
 *  `parent_id` to `parentId` only at mint time (so an already-adopted folder is untouched).
 *  Returns `{ id, wrote }` — `id` is what children hang their `parent_id` on. */
async function stampFolder(
  absDir: string,
  kind: FolderKind,
  parentId: string | null
): Promise<{ id: string; wrote: boolean }> {
  const existing = (await readJsonObject(join(absDir, SIDECAR_FILENAME[kind]))) ?? {}
  const existingId = asString(existing.id)
  if (existingId) return { id: existingId, wrote: false }

  const id = newId()
  const next: Record<string, unknown> = { ...existing, id }
  if (kind === 'set' && parentId) next.parent_id = parentId
  await writeSidecar(absDir, kind, next)
  return { id, wrote: true }
}

/** Stamp `absDir` (as `kind`) then its direct pages, then recurse every non-excluded
 *  subfolder as a Set. Parents are stamped before children. Accumulates the write count. */
async function stampTree(
  absDir: string,
  relDir: string,
  kind: FolderKind,
  parentId: string | null,
  excluded: string[]
): Promise<number> {
  const self = await stampFolder(absDir, kind, parentId)
  let count = self.wrote ? 1 : 0

  for (const e of await listEntries(absDir)) {
    if (e.isFile() && !e.name.startsWith('_') && e.name.toLowerCase().endsWith('.md')) {
      if (await stampPage(join(absDir, e.name))) count++
    } else if (e.isDirectory()) {
      const childRel = `${relDir}/${e.name}`
      if (!shouldSkipDir(e.name, childRel, excluded))
        count += await stampTree(join(absDir, e.name), childRel, 'set', self.id, excluded)
    }
  }
  return count
}

/**
 * Stamp every un-adopted entity under `root`, returning how many writes happened.
 * Top-level folders are Collections; everything nested is a Set. Agenda singleton
 * folders and excluded folders are left alone.
 */
export async function stampAdopted(root: string): Promise<{ stamped: number }> {
  const settings = (await readJsonObject(nexusConfig(root, NEXUS_CONFIG_FILES.settings))) ?? {}
  const excluded = asStringArray(settings.excluded_folders) ?? []

  let stamped = 0
  for (const e of await listEntries(root)) {
    if (!e.isDirectory()) continue
    if (shouldSkipDir(e.name, e.name, excluded)) continue
    if (AGENDA_FOLDER_NAMES.has(e.name)) continue
    const abs = join(root, e.name)
    if (
      (await pathExists(join(abs, SIDECAR_FILENAME.taskConfig))) ||
      (await pathExists(join(abs, SIDECAR_FILENAME.eventConfig)))
    ) {
      continue // Agenda singleton, not a Collection
    }
    stamped += await stampTree(abs, e.name, 'collection', null, excluded)
  }
  return { stamped }
}
