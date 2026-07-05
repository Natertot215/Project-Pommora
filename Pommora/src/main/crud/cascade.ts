// Cascades that keep references consistent when an entity's identity changes: a page
// rename rewrites every inbound `[[link]]` across the nexus; a Context delete strips its
// id from every page's tier array. Both walk the nexus's real pages and rewrite each under
// its file lock (rewritePageSerialized) — the same lock the cell-write path takes, so a
// cascade can't clobber a concurrent edit on a page. Per-file, not cross-file atomic: a
// partly-applied cascade is recoverable by re-running. No SQLite — the inbound set is found
// by scanning; Phase 6's index can narrow this later, but correctness doesn't depend on it.

import { splitFrontmatter } from '../readNexus'
import { splitEnvelope, mergeFrontmatter } from '../io/pageFile'
import { listMarkdownFiles } from '../io/walk'
import { rewritePageSerialized } from '../io/fileLock'
import { scanConnections } from '../connections/scan'
import { rewriteConnections } from '../connections/rewrite'
import { normalizeTitle } from '@shared/connections'
import { tierFieldName } from '@shared/properties'
import { nowIso } from './util'
import { ok, fail, type Result } from '@shared/result'

const SKIP_TOP_LEVEL = ['.nexus', '.trash']

/** Rewrite every page body that links `oldTitle` to link `newTitle`, nexus-wide, atomically.
 *  Body-only rewrite — frontmatter (incl. `modified_at`) is preserved untouched, matching
 *  Swift's cascade (a derived link edit isn't a user modification). Only real pages (with
 *  an `id`) are touched. Returns the touched page paths. The caller renames the target's
 *  own file and reverts that rename if this throws. */
export async function renameCascade(
  nexusRoot: string,
  oldTitle: string,
  newTitle: string
): Promise<Result<{ touched: string[] }>> {
  const oldKey = normalizeTitle(oldTitle)
  const touched: string[] = []
  for (const file of await listMarkdownFiles(nexusRoot, { skipTopLevel: SKIP_TOP_LEVEL })) {
    const wrote = await rewritePageSerialized(file, (content) => {
      const { body } = splitEnvelope(content)
      if (!scanConnections(body).some((c) => c.normalizedTitle === oldKey)) return null
      if (!splitFrontmatter(content).id) return null // connections live only on real pages
      const newBody = rewriteConnections(body, oldTitle, newTitle)
      if (newBody === body) return null
      return mergeFrontmatter(content, {}, [], newBody)
    })
    if (wrote) touched.push(file)
  }
  return ok({ touched })
}

/** Strip a deleted Context's id from the tier-N array of every page that references it,
 *  nexus-wide, atomically. Bumps each touched page's `modified_at` (the page changed).
 *  `tier` must be 1–3. Returns the touched page paths. */
export async function unlinkTier(
  nexusRoot: string,
  contextId: string,
  tier: number
): Promise<Result<{ touched: string[] }>> {
  if (tier < 1 || tier > 3) return fail('invalid-tier', `Tier ${tier} is not 1–3.`)
  const field = tierFieldName(tier)
  const touched: string[] = []
  for (const file of await listMarkdownFiles(nexusRoot, { skipTopLevel: SKIP_TOP_LEVEL })) {
    const wrote = await rewritePageSerialized(file, (content) => {
      const arr = splitFrontmatter(content)[field]
      if (!Array.isArray(arr) || !arr.includes(contextId)) return null
      const next = arr.filter((x) => x !== contextId)
      const body = splitEnvelope(content).body
      return mergeFrontmatter(content, { [field]: next, modified_at: nowIso() }, [field, 'modified_at'], body)
    })
    if (wrote) touched.push(file)
  }
  return ok({ touched })
}
