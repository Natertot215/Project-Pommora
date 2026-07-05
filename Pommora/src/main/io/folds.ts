// The local heading-fold store: `.nexus/folds.json`, keyed by page id. Per-page editor
// UI state lives here — NOT in frontmatter (keeps the portable `.md` clean, no Pommora
// noise leaking to Obsidian) and NOT in the SQLite index (which stays a regeneratable,
// no-user-data, Swift-schema-identical index). Its own dedicated file so the per-page
// map can't bloat a shared store. Inside `.nexus/` it's already outside the content walk
// (exclusion.ts skips dot-folders) and any future body-sync — per-machine by construction.
import { mkdir } from 'node:fs/promises'
import { nexusConfig, nexusDir, NEXUS_CONFIG_FILES } from '../paths'
import { readJsonObject, writeJson } from './atomicWrite'

/** page id → ordinal-disambiguated fold keys (the headings folded on that page). */
export type FoldState = Record<string, string[]>

const foldsPath = (root: string): string => nexusConfig(root, NEXUS_CONFIG_FILES.folds)

/** Lenient read: absent / corrupt → `{}`; keeps only `string[]` entries. */
export async function readFolds(root: string): Promise<FoldState> {
  const obj = await readJsonObject(foldsPath(root))
  if (obj === null) return {}
  const out: FoldState = {}
  for (const [id, value] of Object.entries(obj)) {
    if (Array.isArray(value) && value.every((x) => typeof x === 'string')) {
      out[id] = value as string[]
    }
  }
  return out
}

/** Set (or, with no keys, clear) a page's folded headings. */
export async function writeFolds(root: string, pageId: string, keys: string[]): Promise<void> {
  const current = await readFolds(root)
  if (keys.length === 0) delete current[pageId]
  else current[pageId] = keys
  await mkdir(nexusDir(root), { recursive: true })
  await writeJson(foldsPath(root), current)
}
