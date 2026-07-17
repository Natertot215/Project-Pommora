// Page (.md) CRUD. Pages live as files inside container folders (Type/Collection/Set).
// filename = title (rename = file rename). Every write goes through the foreign-
// preserving page engine; partial updates govern only the keys they name, so they
// never disturb other frontmatter.

import { join, dirname, basename } from 'node:path'
import { rename, readFile } from 'node:fs/promises'
import { newId } from '../ids'
import { writePageFile, mergeFrontmatter, splitEnvelope } from '../io/pageFile'
import { atomicWriteFile, trashWithTimestamp } from '../io/atomicWrite'
import { splitFrontmatter } from '../readNexus'
import { applyPropertyValue, type PropertyValue } from '@shared/propertyValue'
import { tierFieldName } from '@shared/properties'
import { PAGE_MODELED_KEYS } from '@shared/schemas'
import { ok, fail, type Result } from '@shared/result'
import { pathExists, invalidName, nowIso } from './util'

const MD = '.md'

/** Create a `.md` page in `parentDir` with a fresh ULID, empty tiers/properties, and
 *  created/modified timestamps. Optional icon + initial body. */
export async function createPage(
  parentDir: string,
  name: string,
  opts: { icon?: string; body?: string } = {},
): Promise<Result<{ id: string; path: string }>> {
  if (invalidName(name)) return fail('invalid-name', `"${name}" is not a valid name.`, 'page')
  const file = join(parentDir, name + MD)
  if (await pathExists(file)) return fail('exists', `"${name}" already exists.`, 'page')
  const id = newId()
  const now = nowIso()
  const modeled: Record<string, unknown> = {
    id,
    tier1: [],
    tier2: [],
    tier3: [],
    properties: {},
    created_at: now,
    modified_at: now,
  }
  if (opts.icon) modeled.icon = opts.icon
  await writePageFile(file, modeled, PAGE_MODELED_KEYS, opts.body ?? '')
  return ok({ id, path: file })
}

/** Rename a page file (filename = title). No-op when unchanged; bumps modified_at
 *  on a real rename — the title changed, which counts as an edit. */
export async function renamePage(
  absFile: string,
  newName: string,
): Promise<Result<{ path: string }>> {
  if (invalidName(newName)) return fail('invalid-name', `"${newName}" is not a valid name.`, 'page')
  const target = join(dirname(absFile), newName + MD)
  if (target === absFile) return ok({ path: absFile })
  if (await pathExists(target)) return fail('exists', `"${newName}" already exists.`, 'page')
  await rename(absFile, target)
  const existing = await readFile(target, 'utf8')
  const content = mergeFrontmatter(
    existing,
    { modified_at: nowIso() },
    ['modified_at'],
    splitEnvelope(existing).body,
  )
  await atomicWriteFile(target, content)
  return ok({ path: target })
}

/** Delete a page by moving it to the nexus-local .trash (recoverable). */
export async function deletePage(
  nexusRoot: string,
  absFile: string,
): Promise<Result<{ trashedTo: string }>> {
  if (!(await pathExists(absFile))) return fail('not-found', 'Nothing to delete.', 'page')
  return ok({ trashedTo: await trashWithTimestamp(nexusRoot, absFile) })
}

/** Replace the body, bumping modified_at. Governs only modified_at, so all other
 *  frontmatter (id, tiers, properties, foreign keys, comments) is preserved. */
export async function updatePageBody(absFile: string, body: string): Promise<Result<null>> {
  if (!(await pathExists(absFile))) return fail('not-found', 'Page not found.', 'page')
  await writePageFile(absFile, { modified_at: nowIso() }, ['modified_at'], body)
  return ok(null)
}

/** Move a page to a different container folder (same filename) — a pure file rename.
 *  A Page's Collection membership is its folder location, so its prop_<ulid> frontmatter
 *  values re-join the destination schema on next read (unrecognized keys stay as
 *  preserved foreign frontmatter); no strip, no schema logic lives in the move. */
export async function movePage(
  absFile: string,
  newParentDir: string,
): Promise<Result<{ path: string }>> {
  const target = join(newParentDir, basename(absFile))
  if (target === absFile) return ok({ path: absFile })
  if (await pathExists(target))
    return fail('exists', `A page named "${basename(absFile)}" already exists there.`, 'page')
  await rename(absFile, target)
  return ok({ path: target })
}

/**
 * Set or clear one property value on a page. Governs only `properties` + `modified_at`,
 * so all other frontmatter (id, tiers, foreign keys, comments) is preserved. A null
 * value (or the `null` kind) removes the key; otherwise the value is encoded to its
 * on-disk shape via the codec. Sibling properties are untouched.
 */
export async function updatePageProperty(
  absFile: string,
  propertyId: string,
  value: PropertyValue | null,
): Promise<Result<null>> {
  if (!(await pathExists(absFile))) return fail('not-found', 'Page not found.', 'page')
  const existing = await readFile(absFile, 'utf8')
  const props = applyPropertyValue(splitFrontmatter(existing).properties, propertyId, value)
  const body = splitEnvelope(existing).body
  const content = mergeFrontmatter(
    existing,
    { properties: props, modified_at: nowIso() },
    ['properties', 'modified_at'],
    body,
  )
  await atomicWriteFile(absFile, content)
  return ok(null)
}

/**
 * Set a page's tier-N context links — a **bare** ULID array at the frontmatter root
 * (`tier1`/`tier2`/`tier3`, NOT a `$ctx`-tagged property). Governs only that tier field +
 * `modified_at`, so all other frontmatter survives. The array is always written (even
 * empty). `tier` must be 1–3. Ids are stored as given (existence is not checked here).
 */
export async function setPageTier(
  absFile: string,
  tier: number,
  contextIds: string[],
): Promise<Result<null>> {
  if (tier < 1 || tier > 3) return fail('invalid-tier', `Tier ${tier} is not 1–3.`, 'page')
  if (!(await pathExists(absFile))) return fail('not-found', 'Page not found.', 'page')
  const field = tierFieldName(tier)
  const existing = await readFile(absFile, 'utf8')
  const body = splitEnvelope(existing).body
  const content = mergeFrontmatter(
    existing,
    { [field]: contextIds, modified_at: nowIso() },
    [field, 'modified_at'],
    body,
  )
  await atomicWriteFile(absFile, content)
  return ok(null)
}
