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

import { basename, dirname, join, relative, sep } from 'node:path'
import { mkdir, readFile, realpath, rm } from 'node:fs/promises'
import { sessionRoot } from './session'
import { refreshSessionIndex } from './sessionIndex'
import { resolveUnderRoot } from './pathSafety'
import { createPage, renamePage, movePage } from './crud/page'
import { setChildOrder, setStateOrder } from './crud/reorder'
import { createFolderEntity, renameFolderEntity, moveFolderEntity } from './crud/folderEntity'
import { renameCascade, unlinkTier } from './crud/cascade'
import { trashWithTimestamp, pathExists, readJsonObject, mutateJson, atomicWriteBinary, atomicWriteFile } from './io/atomicWrite'
import { splitEnvelope, mergeFrontmatter, readFrontmatterFields } from './io/pageFile'
import { basenameNoMd } from './coerce'
import { contextTierDir, nexusConfig, SIDECAR_FILENAME, NEXUS_CONFIG_FILES, type ContextTier, type SidecarKind } from './paths'
import { ensureIdentity } from './identity'
import { defaultSettingsSeed } from './settings'
import { ok, fail, type Result } from '@shared/result'
import { applyPropertyValue } from '@shared/propertyValue'
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

/** A nested Set's `parent_id` = its parent container's sidecar id (a Collection at depth-1,
 *  a Set deeper). Position is authoritative (both builds heal parent_id from it), so a missing
 *  parent sidecar is non-fatal — the create just omits the field. */
async function parentContainerId(parentDir: string): Promise<string | undefined> {
  for (const kind of ['collection', 'set'] as const) {
    const sc = await readJsonObject(join(parentDir, SIDECAR_FILENAME[kind]))
    if (sc && typeof sc.id === 'string') return sc.id
  }
  return undefined
}

/** POSIX-join a nexus-relative parent with a child basename (`''` parent = the root). */
const relJoin = (parent: string, child: string): string => (parent ? `${parent}/${child}` : child)

/** Decode a `data:image/<subtype>;base64,<data>` URL to its bytes + file extension (jpeg→jpg). */
function decodeImageDataUrl(dataUrl: string): { ext: string; buffer: Buffer } | null {
  const m = /^data:image\/([a-z0-9.+-]+);base64,(.+)$/i.exec(dataUrl)
  if (!m) return null
  const subtype = m[1].toLowerCase()
  return { ext: subtype === 'jpeg' ? 'jpg' : subtype, buffer: Buffer.from(m[2], 'base64') }
}

/** Decode + atomically write an image into `.nexus/assets/<key>/<prefix>-<token>.<ext>`;
 *  returns the nexus-relative path, or null if the data URL isn't a supported image. A FRESH
 *  filename per write is deliberate: a stable name gave every image the same URL, so the
 *  renderer's <img> served the browser-cached previous image on Change/replace. */
async function writeImageAsset(root: string, assetKey: string, dataUrl: string, prefix: string): Promise<string | null> {
  const decoded = decodeImageDataUrl(dataUrl)
  if (!decoded) return null
  const file = `${prefix}-${Math.random().toString(36).slice(2, 10)}.${decoded.ext}`
  const rel = `.nexus/assets/${assetKey}/${file}`
  const absAsset = join(root, '.nexus', 'assets', assetKey, file)
  await mkdir(dirname(absAsset), { recursive: true })
  await atomicWriteBinary(absAsset, decoded.buffer)
  return rel
}

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
      // '' parentPath = the nexus root (new top-level Collection). See createPage.
      const parent = await resolveUnderRoot(root, req.parentPath || '.')
      if (!parent.ok) return relay(parent)
      // A nested Set carries parent_id; a top-level Collection has no parent.
      const extra: Record<string, unknown> = {}
      if (req.kind === 'set') {
        const pid = await parentContainerId(parent.value)
        if (pid) extra.parent_id = pid
      }
      const r = await createDisambiguated(req.name, (name) =>
        createFolderEntity(parent.value, req.kind, name, extra)
      )
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

    case 'setProfileSubtitle': {
      // Read-merge-write settings.json (≤30 chars), preserving every other key so Swift's
      // version/defaults_version/labels/modified_at survive (no migration churn on re-open).
      const subtitle = req.subtitle.slice(0, 30)
      await mutateJson<Record<string, unknown>>(
        nexusConfig(root, NEXUS_CONFIG_FILES.settings),
        defaultSettingsSeed,
        (cur) => ({ ...cur, profile_subtitle: subtitle })
      )
      return { ok: true }
    }

    case 'setProfileImage': {
      // Profile avatar → `.nexus/assets/<nexusID>/profile-<token>.<ext>` (Swift's per-nexus asset
      // dir), path recorded in settings.profile_image (read-merge-write, other keys preserved).
      const settingsPath = nexusConfig(root, NEXUS_CONFIG_FILES.settings)
      const existing = await readJsonObject(settingsPath)
      const prev = typeof existing?.profile_image === 'string' ? existing.profile_image : null
      if (req.dataUrl) {
        const { id: nexusId } = await ensureIdentity(root)
        const rel = await writeImageAsset(root, nexusId, req.dataUrl, 'profile')
        if (!rel) return fault('Unsupported image data.')
        // Set the field first, then delete a replaced file — a failed write never leaves
        // profile_image pointing at a deleted file (mirrors the banner/cover ordering).
        await mutateJson<Record<string, unknown>>(settingsPath, defaultSettingsSeed, (cur) => ({ ...cur, profile_image: rel }))
        if (prev && prev !== rel) await rm(join(root, prev), { force: true }).catch(() => {})
      } else {
        await mutateJson<Record<string, unknown>>(settingsPath, defaultSettingsSeed, (cur) => {
          const next = { ...cur }
          delete next.profile_image
          return next
        })
        if (prev) await rm(join(root, prev), { force: true }).catch(() => {})
      }
      return { ok: true }
    }

    case 'setBanner': {
      // A page's banner is the Swift-compatible `cover` key in its `.md` frontmatter (not a JSON
      // sidecar); the asset folder is keyed by the page id. Foreign frontmatter + body survive.
      if (req.kind === 'page') {
        const resolved = await resolveUnderRoot(root, req.path)
        if (!resolved.ok) return relay(resolved)
        let existing: string
        try {
          existing = await readFile(resolved.value, 'utf8')
        } catch {
          return fault('That page could not be read.')
        }
        const { body } = splitEnvelope(existing)
        const fields = readFrontmatterFields(existing)
        const id = typeof fields.id === 'string' ? fields.id : null
        if (!id) return fault('That page has no id to key its banner.')
        const prev = typeof fields.cover === 'string' ? fields.cover : null
        if (req.dataUrl) {
          const rel = await writeImageAsset(root, id, req.dataUrl, 'banner')
          if (!rel) return fault('Unsupported image data.')
          await atomicWriteFile(resolved.value, mergeFrontmatter(existing, { cover: rel }, ['cover'], body))
          if (prev && prev !== rel) await rm(join(root, prev), { force: true }).catch(() => {})
        } else {
          await atomicWriteFile(resolved.value, mergeFrontmatter(existing, {}, ['cover'], body))
          if (prev) await rm(join(root, prev), { force: true }).catch(() => {})
        }
        void refreshSessionIndex(root)
        return { ok: true }
      }
      // Resolve the config holding the banner field + the asset-folder key, per owner kind. The
      // homepage is a singleton (.nexus/homepage.json, keyed 'homepage'); the rest are folder
      // sidecars keyed by their entity id (matches Swift's per-entity assets/<id>/).
      let cfgPath: string
      let assetKey: string
      let fallback: Record<string, unknown>
      let existing: Record<string, unknown> | null
      if (req.kind === 'homepage') {
        cfgPath = nexusConfig(root, NEXUS_CONFIG_FILES.homepage)
        assetKey = 'homepage'
        fallback = {}
        existing = await readJsonObject(cfgPath)
      } else {
        const resolved = await resolveUnderRoot(root, req.path)
        if (!resolved.ok) return relay(resolved)
        if (await isReserved(root, resolved.value)) return fault('That item can’t take a banner.')
        cfgPath = `${resolved.value}/${SIDECAR_FILENAME[req.kind]}`
        existing = await readJsonObject(cfgPath)
        const id = typeof existing?.id === 'string' ? existing.id : null
        if (!id) return fault('That item has no id to key its banner.')
        assetKey = id
        fallback = { id }
      }
      const prev = typeof existing?.banner === 'string' ? existing.banner : null
      if (req.dataUrl) {
        const rel = await writeImageAsset(root, assetKey, req.dataUrl, 'banner')
        if (!rel) return fault('Unsupported image data.')
        // Set the field first; only THEN delete a replaced file, so a failed write never
        // leaves `banner` pointing at a deleted file (mirrors the cover/photo ordering).
        await mutateJson<Record<string, unknown>>(cfgPath, () => fallback, (cur) => ({ ...cur, banner: rel }))
        if (prev && prev !== rel) await rm(join(root, prev), { force: true }).catch(() => {})
      } else {
        await mutateJson<Record<string, unknown>>(cfgPath, () => fallback, (cur) => {
          const next = { ...cur }
          delete next.banner
          return next
        })
        if (prev) await rm(join(root, prev), { force: true }).catch(() => {})
      }
      void refreshSessionIndex(root)
      return { ok: true }
    }

    case 'setProperty': {
      // One typed property write into a page's `.md` frontmatter `properties` map; foreign frontmatter
      // + body survive (same shape as the page-banner cover write). applyPropertyValue is the shared
      // set/clear rule — a null value deletes the key. Drives table cross-group reassignment (D-4).
      const resolved = await resolveUnderRoot(root, req.path)
      if (!resolved.ok) return relay(resolved)
      let existing: string
      try {
        existing = await readFile(resolved.value, 'utf8')
      } catch {
        return fault('That page could not be read.')
      }
      const { body } = splitEnvelope(existing)
      const fields = readFrontmatterFields(existing)
      const properties = applyPropertyValue(fields.properties, req.propertyId, req.value)
      await atomicWriteFile(resolved.value, mergeFrontmatter(existing, { properties }, ['properties'], body))
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
      // Reorder top Collections / a context tier — persisted to .nexus/state.json.
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
