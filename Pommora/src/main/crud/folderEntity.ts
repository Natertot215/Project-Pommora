// ONE generic CRUD for every folder-shaped entity — Areas, Topics, Projects, Page
// Types, Page Collections, Page Sets. Swift expressed this as several managers with
// copy-pasted create/rename/delete/rollback ladders; here it's a single source.
//
// Invariants: filename = title (rename = folder rename); a fresh entity gets a real
// ULID; delete moves to the in-nexus .trash. Foreign sidecar keys are preserved on
// update (readSidecar retains them via looseObject, and we spread the read object).

import { mkdir, rename } from 'node:fs/promises'
import { join, dirname, basename } from 'node:path'
import type { z } from 'zod'
import { newId } from '../ids'
import { readSidecar, writeSidecar } from '../sidecarIO'
import { trashWithTimestamp } from '../io/atomicWrite'
import { recordWrite } from '../io/writeEcho'
import { pathExists, invalidName } from './util'
import type { SidecarKind } from '../paths'
import { ok, fail, type Result } from '@shared/result'

/** Create a folder entity: make the folder + write its sidecar with a fresh ULID and
 *  `extra` fields (e.g. `{ tier }` for a context, `{ color }` for an area). */
export async function createFolderEntity(
  parentDir: string,
  kind: SidecarKind,
  name: string,
  extra: Record<string, unknown> = {}
): Promise<Result<{ id: string; path: string }>> {
  if (invalidName(name)) return fail('invalid-name', `"${name}" is not a valid name.`, kind)
  const folder = join(parentDir, name)
  if (await pathExists(folder)) return fail('exists', `"${name}" already exists.`, kind)
  const id = newId()
  await mkdir(folder, { recursive: true })
  // Suppress the new folder's addDir echo (the sidecar write self-suppresses via atomicWrite, the mkdir
  // doesn't): the create already refetches explicitly, and an un-suppressed watcher swap mid-rename
  // remounts the fresh row and drops the inline-rename keystrokes.
  recordWrite(folder)
  await writeSidecar(folder, kind, { id, ...extra })
  return ok({ id, path: folder })
}

/** Rename a folder entity (filename = title). No-op if the name is unchanged. */
export async function renameFolderEntity(
  absFolder: string,
  newName: string
): Promise<Result<{ path: string }>> {
  if (invalidName(newName)) return fail('invalid-name', `"${newName}" is not a valid name.`)
  const target = join(dirname(absFolder), newName)
  if (target === absFolder) return ok({ path: absFolder })
  if (await pathExists(target)) return fail('exists', `"${newName}" already exists.`)
  await rename(absFolder, target)
  return ok({ path: target })
}

/** Move a folder entity into a different parent folder (same name). No-op when it's already
 *  there. The whole subtree (its pages + sidecar) moves with it. movePage, folder-level. */
export async function moveFolderEntity(
  absFolder: string,
  newParentDir: string
): Promise<Result<{ path: string }>> {
  const target = join(newParentDir, basename(absFolder))
  if (target === absFolder) return ok({ path: absFolder })
  if (await pathExists(target)) return fail('exists', `"${basename(absFolder)}" already exists there.`)
  await rename(absFolder, target)
  return ok({ path: target })
}

/** Delete a folder entity by moving it to the nexus-local .trash (recoverable). */
export async function deleteFolderEntity(
  nexusRoot: string,
  absFolder: string
): Promise<Result<{ trashedTo: string }>> {
  if (!(await pathExists(absFolder))) return fail('not-found', 'Nothing to delete.')
  return ok({ trashedTo: await trashWithTimestamp(nexusRoot, absFolder) })
}

/** Read-modify-write a folder entity's sidecar, merging `patch` over the current
 *  (foreign keys retained). Returns the written sidecar. */
export async function updateFolderSidecar<S extends z.ZodType>(
  absFolder: string,
  kind: SidecarKind,
  schema: S,
  patch: Partial<z.infer<S>>
): Promise<Result<z.infer<S>>> {
  const current = await readSidecar(absFolder, kind, schema)
  if (current === null) return fail('not-found', 'Sidecar not found or invalid.', kind)
  const next = { ...current, ...patch }
  await writeSidecar(absFolder, kind, next)
  return ok(next)
}
