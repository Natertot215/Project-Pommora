// The local table heading-column store: `.nexus/tableHeadingColumns.json`, keyed by page id → the
// indices of the tables on that page whose first column is rendered as a heading. Same rationale as
// the fold store (see io/folds.ts): a heading column is a Pommora-only visual with no GFM equivalent,
// so it lives OUT of the portable `.md` (no noise leaking to Obsidian) and OUT of the regeneratable
// index. Tables are keyed by their position on the page — stable unless whole tables are added/removed
// above a styled one (an accepted v1 limitation, matching the fold store's ordinal fragility; slightly
// worse here — a stale index mis-styles whatever table now sits at it, where a stale fold key just no-ops).
import { mkdir } from 'node:fs/promises'
import { nexusConfig, nexusDir, NEXUS_CONFIG_FILES } from '../paths'
import { readJsonObject, writeJson } from './atomicWrite'

/** page id → indices of that page's tables with a heading column. */
export type TableHeadingColState = Record<string, number[]>

const storePath = (root: string): string =>
  nexusConfig(root, NEXUS_CONFIG_FILES.tableHeadingColumns)

/** Lenient read: absent / corrupt → `{}`; keeps only non-negative-integer arrays. */
export async function readTableHeadingColumns(root: string): Promise<TableHeadingColState> {
  const obj = await readJsonObject(storePath(root))
  if (obj === null) return {}
  const out: TableHeadingColState = {}
  for (const [id, value] of Object.entries(obj)) {
    if (Array.isArray(value) && value.every((x) => Number.isInteger(x) && x >= 0)) {
      out[id] = value as number[]
    }
  }
  return out
}

/** Set (or, with no indices, clear) a page's heading-column tables. */
export async function writeTableHeadingColumns(
  root: string,
  pageId: string,
  indices: number[],
): Promise<void> {
  const current = await readTableHeadingColumns(root)
  if (indices.length === 0) delete current[pageId]
  else current[pageId] = indices
  await mkdir(nexusDir(root), { recursive: true })
  await writeJson(storePath(root), current)
}
