// Page (.md) CRUD. Pages live as files inside container folders (Type/Collection/Set).
// filename = title (rename = file rename). Every write goes through the foreign-
// preserving page engine; partial updates govern only the keys they name, so they
// never disturb other frontmatter.

import { join, dirname, basename } from 'node:path'
import { rename, stat } from 'node:fs/promises'
import { newId } from '../ids'
import { writePageFile } from '../io/pageFile'
import { trashWithTimestamp } from '../io/atomicWrite'
import { PAGE_MODELED_KEYS } from '@shared/schemas'
import { ok, fail, type Result } from '@shared/result'

const MD = '.md'

function nowIso(): string {
  return new Date().toISOString()
}

async function exists(p: string): Promise<boolean> {
  try {
    await stat(p)
    return true
  } catch {
    return false
  }
}

function invalidName(name: string): boolean {
  return !name.trim() || name.includes('/') || name.includes('\\') || name === '.' || name === '..'
}

/** Create a `.md` page in `parentDir` with a fresh ULID, empty tiers/properties, and
 *  created/modified timestamps. Optional icon + initial body. */
export async function createPage(
  parentDir: string,
  name: string,
  opts: { icon?: string; body?: string } = {}
): Promise<Result<{ id: string; path: string }>> {
  if (invalidName(name)) return fail('invalid-name', `"${name}" is not a valid name.`, 'page')
  const file = join(parentDir, name + MD)
  if (await exists(file)) return fail('exists', `"${name}" already exists.`, 'page')
  const id = newId()
  const now = nowIso()
  const modeled: Record<string, unknown> = {
    id,
    tier1: [],
    tier2: [],
    tier3: [],
    properties: {},
    created_at: now,
    modified_at: now
  }
  if (opts.icon) modeled.icon = opts.icon
  await writePageFile(file, modeled, PAGE_MODELED_KEYS, opts.body ?? '')
  return ok({ id, path: file })
}

/** Rename a page file (filename = title). No-op when unchanged. */
export async function renamePage(absFile: string, newName: string): Promise<Result<{ path: string }>> {
  if (invalidName(newName)) return fail('invalid-name', `"${newName}" is not a valid name.`, 'page')
  const target = join(dirname(absFile), newName + MD)
  if (target === absFile) return ok({ path: absFile })
  if (await exists(target)) return fail('exists', `"${newName}" already exists.`, 'page')
  await rename(absFile, target)
  return ok({ path: target })
}

/** Delete a page by moving it to the nexus-local .trash (recoverable). */
export async function deletePage(nexusRoot: string, absFile: string): Promise<Result<{ trashedTo: string }>> {
  if (!(await exists(absFile))) return fail('not-found', 'Nothing to delete.', 'page')
  return ok({ trashedTo: await trashWithTimestamp(nexusRoot, absFile) })
}

/** Replace the body, bumping modified_at. Governs only modified_at, so all other
 *  frontmatter (id, tiers, properties, foreign keys, comments) is preserved. */
export async function updatePageBody(absFile: string, body: string): Promise<Result<null>> {
  if (!(await exists(absFile))) return fail('not-found', 'Page not found.', 'page')
  await writePageFile(absFile, { modified_at: nowIso() }, ['modified_at'], body)
  return ok(null)
}

/** Move a page to a different container folder (same filename). Cross-type property
 *  stripping is a Phase-4 concern (needs the target schema) — this relocates the file. */
export async function movePage(absFile: string, newParentDir: string): Promise<Result<{ path: string }>> {
  const target = join(newParentDir, basename(absFile))
  if (target === absFile) return ok({ path: absFile })
  if (await exists(target)) return fail('exists', `A page named "${basename(absFile)}" already exists there.`, 'page')
  await rename(absFile, target)
  return ok({ path: target })
}
