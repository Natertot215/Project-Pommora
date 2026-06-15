// Cascades that keep references consistent when an entity's identity changes: a page
// rename rewrites every inbound `[[link]]` across the nexus; a Context delete strips its
// id from every page's tier array. Both walk the nexus's real pages and commit their
// rewrites atomically via SchemaTransaction (all touched files land together-or-not-at-
// all), so a half-applied cascade never lingers. No SQLite — the inbound set is found by
// scanning; Phase 6's index can narrow this later, but correctness doesn't depend on it.

import { readFile } from 'node:fs/promises'
import { splitFrontmatter } from '../readNexus'
import { splitEnvelope, mergeFrontmatter } from '../io/pageFile'
import { listMarkdownFiles } from '../io/walk'
import { SchemaTransaction } from '../io/schemaTransaction'
import { scanConnections } from '../connections/scan'
import { rewriteConnections } from '../connections/rewrite'
import { normalizeTitle } from '@shared/connections'
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
  const tx = new SchemaTransaction()
  const touched: string[] = []
  for (const file of await listMarkdownFiles(nexusRoot, { skipTopLevel: SKIP_TOP_LEVEL })) {
    let content: string
    try {
      content = await readFile(file, 'utf8')
    } catch {
      continue
    }
    const { body } = splitEnvelope(content)
    if (!scanConnections(body).some((c) => c.normalizedTitle === oldKey)) continue
    if (!splitFrontmatter(content).id) continue // connections live only on real pages
    const newBody = rewriteConnections(body, oldTitle, newTitle)
    if (newBody === body) continue
    tx.stage(file, mergeFrontmatter(content, {}, [], newBody))
    touched.push(file)
  }
  if (touched.length > 0) await tx.commit()
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
  const field = `tier${tier}`
  const tx = new SchemaTransaction()
  const touched: string[] = []
  for (const file of await listMarkdownFiles(nexusRoot, { skipTopLevel: SKIP_TOP_LEVEL })) {
    let content: string
    try {
      content = await readFile(file, 'utf8')
    } catch {
      continue
    }
    const arr = splitFrontmatter(content)[field]
    if (!Array.isArray(arr) || !arr.includes(contextId)) continue
    const next = arr.filter((x) => x !== contextId)
    const body = splitEnvelope(content).body
    tx.stage(
      file,
      mergeFrontmatter(content, { [field]: next, modified_at: nowIso() }, [field, 'modified_at'], body)
    )
    touched.push(file)
  }
  if (touched.length > 0) await tx.commit()
  return ok({ touched })
}
