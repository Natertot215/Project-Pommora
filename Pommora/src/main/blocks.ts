// The BlockHost read/write path (D-2): the block document lives on the host's own
// config — homepage.json for the dev host (G-12) — and every write is a locked
// read-merge-write, so layout/blocks/blocks_locked are the ONLY keys touched and
// foreign keys (banner included) survive. All homepage.json writers serialize on
// the config path: this module and setBanner's homepage branch share the lock, or
// a banner write racing a debounced layout write becomes a whole-file lost update.

import { mkdir, readFile, rm } from 'node:fs/promises'
import { join } from 'node:path'
import { knownBlock, type BlockDoc, type BlockDocPatch, type BlockHostRef } from '@shared/blocks'
import { newId } from './ids'
import { atomicWriteFile, mutateJson, pathExists, readJsonObject, trashWithTimestamp } from './io/atomicWrite'
import { serializeOnFile } from './io/fileLock'
import { blockHostDir, nexusConfig, NEXUS_CONFIG_FILES } from './paths'

/** The host's own config carries the block document (D-2/D-3 — one file, one
 *  entity). Its writes don't cost a re-walk: the app's own writes are echo-
 *  suppressed at the watcher (io/writeEcho). */
export function blockHostConfig(root: string, _host: BlockHostRef): string {
  return nexusConfig(root, NEXUS_CONFIG_FILES.homepage)
}

/** A markdown block's backing file: `<tile-ulid>.md` in the host's own folder (D-11). */
export function blockFilePath(root: string, host: BlockHostRef, tileId: string): string {
  return join(blockHostDir(root, host), `${tileId}.md`)
}

/** The one locked read-merge-write every doc mutation goes through. */
async function mutateDoc(
  root: string,
  host: BlockHostRef,
  fn: (cur: Record<string, unknown>) => Record<string, unknown>
): Promise<void> {
  const path = blockHostConfig(root, host)
  await serializeOnFile(path, () => mutateJson<Record<string, unknown>>(path, () => ({}), fn))
}

/** One-time healing: a brief interim build split the doc into a `_blocks.json`
 *  sidecar — fold it back onto the host config (one file, one entity) and remove
 *  it. No-op when no sidecar exists. */
async function healSplitDoc(root: string, host: BlockHostRef): Promise<void> {
  const sidecarPath = join(blockHostDir(root, host), '_blocks.json')
  const sidecar = await readJsonObject(sidecarPath)
  if (!sidecar) return
  await mutateDoc(root, host, (cur) => ({
    ...cur,
    ...('layout' in sidecar ? { layout: sidecar.layout } : {}),
    ...('blocks' in sidecar ? { blocks: sidecar.blocks } : {}),
    ...('blocks_locked' in sidecar ? { blocks_locked: sidecar.blocks_locked } : {})
  }))
  await rm(sidecarPath, { force: true })
}

export async function readBlockDoc(root: string, host: BlockHostRef): Promise<BlockDoc> {
  await healSplitDoc(root, host)
  const raw = await readJsonObject(blockHostConfig(root, host))
  return {
    layout: raw?.layout,
    blocks: Array.isArray(raw?.blocks) ? raw.blocks : [],
    locked: raw?.blocks_locked === true
  }
}

export async function writeBlockDoc(root: string, host: BlockHostRef, patch: BlockDocPatch): Promise<void> {
  await mutateDoc(root, host, (cur) => {
    const next = { ...cur }
    if ('layout' in patch) next.layout = patch.layout
    if ('blocks' in patch) next.blocks = patch.blocks
    if ('locked' in patch) {
      if (patch.locked) next.blocks_locked = true
      else delete next.blocks_locked
    }
    return next
  })
}

/** Mint a markdown block: host dir, an empty `<ulid>.md`, then the `blocks[]` entry —
 *  in that order, so a crash leaks at worst an orphan file, never an entry without one.
 *  The renderer splices the layout leaf afterward. */
export async function createMarkdownBlock(root: string, host: BlockHostRef): Promise<string> {
  const id = newId()
  await mkdir(blockHostDir(root, host), { recursive: true })
  await atomicWriteFile(blockFilePath(root, host, id), '')
  await mutateDoc(root, host, (cur) => {
    const blocks = Array.isArray(cur.blocks) ? cur.blocks : []
    return { ...cur, blocks: [...blocks, { id, type: 'markdown' }] }
  })
  return id
}

/** Drop a tile's entry; a markdown tile's backing `.md` goes to `.trash` (E-5). Foreign
 *  entries are never touched (E-1). The renderer splices the layout leaf FIRST — if this
 *  op is what fails, the leftover is an entry-less invisible orphan, never a dead box. */
export async function removeBlockTile(root: string, host: BlockHostRef, tileId: string): Promise<void> {
  let wasMarkdown = false
  await mutateDoc(root, host, (cur) => {
    const blocks = Array.isArray(cur.blocks) ? cur.blocks : []
    const kept = blocks.filter((b) => {
      const entry = knownBlock(b)
      if (entry?.id !== tileId) return true
      if (entry.type === 'markdown') wasMarkdown = true
      return false
    })
    return { ...cur, blocks: kept }
  })
  if (wasMarkdown) await trashTileFile(root, host, tileId)
}

/** Trash a markdown tile's backing file on ITS lock — ordered against a still-pending
 *  editor flush, so a late body write can never land after the trash and resurrect it. */
async function trashTileFile(root: string, host: BlockHostRef, tileId: string): Promise<void> {
  const file = blockFilePath(root, host, tileId)
  await serializeOnFile(file, async () => {
    if (await pathExists(file)) await trashWithTimestamp(root, file)
  })
}

/** Linking IS the one conversion (G-7, markdown → embed): the RAW entry spreads so
 *  foreign keys + chrome survive (E-1), the backing `.md` trashes recoverably (E-5),
 *  and the embedded source is never touched. */
async function flipTile(root: string, host: BlockHostRef, tileId: string, patch: Record<string, unknown>): Promise<void> {
  let wasMarkdown = false
  await mutateDoc(root, host, (cur) => {
    const blocks = Array.isArray(cur.blocks) ? cur.blocks : []
    const next = blocks.map((b) => {
      const entry = knownBlock(b)
      if (entry?.id !== tileId) return b
      if (entry.type === 'markdown') wasMarkdown = true
      return { ...(b as Record<string, unknown>), ...patch }
    })
    return { ...cur, blocks: next }
  })
  if (wasMarkdown) await trashTileFile(root, host, tileId)
}

export async function convertTileToPage(root: string, host: BlockHostRef, tileId: string, pageId: string): Promise<void> {
  await flipTile(root, host, tileId, { type: 'page', page_id: pageId })
}

/** Link View: the entry becomes a view embed carrying the COPIED config(s) (D-12).
 *  Each config's `id` is re-minted here as a payload-local ULID — the source view's id
 *  and the DEFAULT_VIEW_ID sentinel are both live keys outside the payload, and a
 *  preserved one would silently re-couple the "detached" snapshot to its source. */
export async function convertTileToView(root: string, host: BlockHostRef, tileId: string, views: unknown[]): Promise<void> {
  const stamped = views.map((v) => {
    if (typeof v !== 'object' || v === null) return v
    const el = v as Record<string, unknown>
    if (typeof el.config !== 'object' || el.config === null) return el
    return { ...el, config: { ...(el.config as Record<string, unknown>), id: newId() } }
  })
  await flipTile(root, host, tileId, { type: 'view', views: stamped, active: 0 })
}

export async function readMarkdownBlock(root: string, host: BlockHostRef, tileId: string): Promise<string | null> {
  try {
    return await readFile(blockFilePath(root, host, tileId), 'utf8')
  } catch {
    return null
  }
}

/** Pure body write — no frontmatter envelope, no stamp (D-11: block files stay bare).
 *  Locked on the file so a future rename-cascade rewrite can't clobber a live edit. */
export async function writeMarkdownBlock(root: string, host: BlockHostRef, tileId: string, body: string): Promise<void> {
  const file = blockFilePath(root, host, tileId)
  await serializeOnFile(file, () => atomicWriteFile(file, body))
}
