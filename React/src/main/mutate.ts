// The single write orchestration behind the `mutate` IPC. Each request carries nexus-
// relative paths; main resolves them under the session root (resolveUnderRoot), runs the
// matching crud/* op, applies the cascade policy, then fire-and-forgets the index refresh
// (off the UI critical path — the renderer's tree comes from readNexus, not the index, so
// the response returns the instant the files are written). Returns a MutateResult (never
// throws across the boundary).
//
// Cascade policy (the load-bearing part of Swift's design, owned here so no call site
// re-invents it):
//   • page rename  → renameCascade rewrites inbound [[links]]; the file rename is reverted
//                    if the cascade fails (Result error OR throw).
//   • context delete → unlinkTier strips the context id from every page's tier array BEFORE
//                    the folder is removed, so no page keeps a dangling tier ref.
// System-trash is injected (deps.trashToSystem) so this module stays Electron-free + testable.

import { basename, relative, sep } from 'node:path'
import { realpath } from 'node:fs/promises'
import { sessionRoot } from './session'
import { refreshSessionIndex } from './sessionIndex'
import { resolveUnderRoot } from './pathSafety'
import { createPage, renamePage, movePage } from './crud/page'
import { setChildOrder, setStateOrder } from './crud/reorder'
import { createFolderEntity, renameFolderEntity, moveFolderEntity } from './crud/folderEntity'
import { renameCascade, unlinkTier } from './crud/cascade'
import { trashWithTimestamp, pathExists, readJsonObject } from './io/atomicWrite'
import { basenameNoMd } from './coerce'
import { contextTierDir, SIDECAR_FILENAME, type ContextTier, type SidecarKind } from './paths'
import { ok, fail, type Result } from '@shared/result'
import type { MutateRequest, MutateResult } from '@shared/mutate'
import type { TrashMode } from './appConfig'

/** What the orchestration needs from the Electron layer (injected to keep this testable). */
export interface MutateDeps {
  trashMode: TrashMode
  /** Move a path to the OS trash (shell.trashItem). Only the 'system' trashMode uses it. */
  trashToSystem: (absPath: string) => Promise<void>
}

const CONTEXT_TIER: Record<'area' | 'topic' | 'project', 1 | 2 | 3> = { area: 1, topic: 2, project: 3 }
const CONTEXT_KIND_BY_TIER: Record<1 | 2 | 3, SidecarKind> = { 1: 'area', 2: 'topic', 3: 'project' }
const TIER_DIR: Record<1 | 2 | 3, ContextTier> = { 1: 'areas', 2: 'topics', 3: 'projects' }

/** POSIX-join a nexus-relative parent with a child basename (`''` parent = the root). */
const relJoin = (parent: string, child: string): string => (parent ? `${parent}/${child}` : child)

/** The nexus's own machinery — never a renderer-mutable entity. The read side skips these,
 *  so the write side refuses to rename/delete them (defense against a buggy/hostile renderer
 *  message). Contexts live UNDER `.nexus/<tier>/` and stay mutable — only the root, `.nexus`
 *  itself, and `.trash` are off-limits. `abs` is canonical (resolveUnderRoot realpaths it), so
 *  the root is canonicalized too — else a symlinked root (e.g. macOS /var→/private/var) makes
 *  `relative` mismatch and the guard silently passes. */
async function isReserved(root: string, abs: string): Promise<boolean> {
  const rel = relative(await realpath(root), abs)
  return rel === '' || rel === '.nexus' || rel === '.trash' || rel.startsWith('.trash' + sep)
}

/** Map a failed data-layer Result onto a MutateResult; pass an ok Result through as a bare ok. */
function relay<T>(r: Result<T>): MutateResult {
  return r.ok ? { ok: true } : { ok: false, error: r.error }
}

const fault = (message: string): MutateResult => ({ ok: false, error: { code: 'operation-failed', message } })

/**
 * Create with a base name, disambiguating on collision: base, "base 2", "base 3", … The
 * "New …" UX — a fresh entity should always appear, never silently fail on a name clash.
 * Only creates disambiguate; rename stays strict (renaming onto an existing name is an error).
 */
async function createDisambiguated(
  baseName: string,
  attempt: (name: string) => Promise<Result<{ id: string; path: string }>>
): Promise<Result<{ id: string; path: string }>> {
  let last = await attempt(baseName)
  for (let n = 2; n <= 50 && !last.ok && last.error.code === 'exists'; n++) {
    last = await attempt(`${baseName} ${n}`)
  }
  return last
}

export async function handleMutate(req: MutateRequest, deps: MutateDeps): Promise<MutateResult> {
  const root = sessionRoot()
  if (root === null) return fault('No nexus is open.')
  // The contract is "never throws across the boundary": a CRUD/fs/trash throw (e.g.
  // shell.trashItem rejecting, EACCES/ENOSPC) becomes a fault Result, not a rejected IPC
  // promise the callers (store.newPage / contextMenu) silently swallow.
  try {
    return await dispatch(req, deps, root)
  } catch (e) {
    return fault(e instanceof Error ? e.message : String(e))
  }
}

async function dispatch(req: MutateRequest, deps: MutateDeps, root: string): Promise<MutateResult> {
  switch (req.op) {
    case 'createPage': {
      // '' parentPath = the nexus root (e.g. a page directly under an adopted root); '.'
      // is the existing dir resolveUnderRoot validates. relJoin keeps '' for the rel path.
      const parent = await resolveUnderRoot(root, req.parentPath || '.')
      if (!parent.ok) return relay(parent)
      const r = await createDisambiguated(req.name, (name) => createPage(parent.value, name))
      if (!r.ok) return relay(r)
      void refreshSessionIndex(root)
      return { ok: true, created: { id: r.value.id, path: relJoin(req.parentPath, basename(r.value.path)) } }
    }

    case 'createContainer': {
      // '' parentPath = the nexus root (new vault). See createPage.
      const parent = await resolveUnderRoot(root, req.parentPath || '.')
      if (!parent.ok) return relay(parent)
      const r = await createDisambiguated(req.name, (name) => createFolderEntity(parent.value, req.kind, name))
      if (!r.ok) return relay(r)
      void refreshSessionIndex(root)
      return { ok: true, created: { id: r.value.id, path: relJoin(req.parentPath, basename(r.value.path)) } }
    }

    case 'createContext': {
      // The tier dir is main-derived (under root by construction), so it bypasses the
      // renderer-path guard; createFolderEntity mkdir's it (recursive) if absent.
      const dir = contextTierDir(root, TIER_DIR[req.tier])
      const r = await createDisambiguated(req.name, (name) => createFolderEntity(dir, CONTEXT_KIND_BY_TIER[req.tier], name))
      if (!r.ok) return relay(r)
      void refreshSessionIndex(root)
      return { ok: true, created: { id: r.value.id, path: `.nexus/${TIER_DIR[req.tier]}/${basename(r.value.path)}` } }
    }

    case 'rename': {
      const resolved = await resolveUnderRoot(root, req.path)
      if (!resolved.ok) return relay(resolved)
      const abs = resolved.value
      if (await isReserved(root, abs)) return fault('That item can’t be renamed.')
      if (req.kind === 'page') {
        const oldTitle = basenameNoMd(basename(abs))
        const r = await renamePage(abs, req.newName)
        if (!r.ok) return relay(r)
        // Rewrite inbound [[links]] nexus-wide; revert the file rename if the cascade fails.
        try {
          const cascade = await renameCascade(root, oldTitle, req.newName)
          if (!cascade.ok) {
            await renamePage(r.value.path, oldTitle)
            return relay(cascade)
          }
        } catch {
          await renamePage(r.value.path, oldTitle)
          return fault('Rename cascade failed; the rename was reverted.')
        }
        void refreshSessionIndex(root)
        return { ok: true }
      }
      // Containers + contexts: rename the folder. No link cascade — [[links]] target pages,
      // and contexts are referenced by stable id (the rename only changes the display title).
      const r = await renameFolderEntity(abs, req.newName)
      if (!r.ok) return relay(r)
      void refreshSessionIndex(root)
      return { ok: true }
    }

    case 'delete': {
      const resolved = await resolveUnderRoot(root, req.path)
      if (!resolved.ok) return relay(resolved)
      const abs = resolved.value
      if (await isReserved(root, abs)) return fault('That item can’t be deleted.')
      if (req.kind === 'area' || req.kind === 'topic' || req.kind === 'project') {
        // Strip this context's id from every page's tier array before removing the folder.
        const sidecar = await readJsonObject(`${abs}/${SIDECAR_FILENAME[req.kind]}`)
        const id = typeof sidecar?.id === 'string' ? sidecar.id : null
        if (id) await unlinkTier(root, id, CONTEXT_TIER[req.kind])
      }
      const removed = await removeViaMode(root, abs, deps)
      if (!removed.ok) return relay(removed)
      void refreshSessionIndex(root)
      return { ok: true }
    }

    case 'movePage': {
      const src = await resolveUnderRoot(root, req.path)
      if (!src.ok) return relay(src)
      const dst = await resolveUnderRoot(root, req.newParentPath)
      if (!dst.ok) return relay(dst)
      const r = await movePage(src.value, dst.value)
      if (!r.ok) return relay(r)
      // Persist the destination's new page order (reorder + drop-at-position). The source's
      // stale id self-drops on the next read, so only the destination is rewritten.
      if (req.order) {
        const o = await setChildOrder(dst.value, 'page_order', req.order)
        if (!o.ok) return relay(o)
      }
      void refreshSessionIndex(root)
      return { ok: true }
    }

    case 'moveSet': {
      // Move a set folder between collections (within its vault) or reorder it in place, then
      // write the destination collection's set_order. The set's pages travel inside the folder.
      const src = await resolveUnderRoot(root, req.path)
      if (!src.ok) return relay(src)
      const dst = await resolveUnderRoot(root, req.newParentPath)
      if (!dst.ok) return relay(dst)
      const r = await moveFolderEntity(src.value, dst.value)
      if (!r.ok) return relay(r)
      const o = await setChildOrder(dst.value, 'set_order', req.order)
      if (!o.ok) return relay(o)
      void refreshSessionIndex(root)
      return { ok: true }
    }

    case 'reorderChildren': {
      // Reorder collections within a vault / sets within a collection — order-only, no move.
      const parent = await resolveUnderRoot(root, req.parentPath)
      if (!parent.ok) return relay(parent)
      const o = await setChildOrder(parent.value, req.key, req.order)
      if (!o.ok) return relay(o)
      void refreshSessionIndex(root)
      return { ok: true }
    }

    case 'reorderTop': {
      // Reorder vaults / a context tier — persisted to .nexus/state.json.
      const o = await setStateOrder(root, req.key, req.order)
      if (!o.ok) return relay(o)
      void refreshSessionIndex(root)
      return { ok: true }
    }

    default: {
      const _exhaustive: never = req
      void _exhaustive
      return fault('Unknown operation.')
    }
  }
}

/** Remove a file/folder per the delete-target setting: in-nexus .trash (default, portable +
 *  recoverable) or the OS Trash. trashWithTimestamp is the shared primitive crud's delete*
 *  uses; this adds the mode branch the crud helpers don't cover. */
async function removeViaMode(root: string, abs: string, deps: MutateDeps): Promise<Result<null>> {
  if (!(await pathExists(abs))) return fail('not-found', 'Nothing to delete.')
  if (deps.trashMode === 'system') await deps.trashToSystem(abs)
  else await trashWithTimestamp(root, abs)
  return ok(null)
}
