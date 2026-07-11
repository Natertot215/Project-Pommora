// The BlockHost read/write path (D-2): the block document lives on the host's own
// config — homepage.json for the dev host (G-12) — and every write is a locked
// read-merge-write, so layout/blocks/blocks_locked are the ONLY keys touched and
// foreign keys (banner included) survive. All homepage.json writers serialize on
// the config path: this module and setBanner's homepage branch share the lock, or
// a banner write racing a debounced layout write becomes a whole-file lost update.

import { mkdir, readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { knownBlock, type BlockDoc, type BlockDocPatch, type BlockHostRef } from '@shared/blocks'
import { newId } from './ids'
import { atomicWriteFile, mutateJson, pathExists, readJsonObject, trashWithTimestamp } from './io/atomicWrite'
import { serializeOnFile } from './io/fileLock'
import { blockHostDir, nexusConfig, NEXUS_CONFIG_FILES } from './paths'

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

export async function readBlockDoc(root: string, host: BlockHostRef): Promise<BlockDoc> {
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
  if (wasMarkdown) {
    const file = blockFilePath(root, host, tileId)
    if (await pathExists(file)) await trashWithTimestamp(root, file)
  }
}

/** Turn Into → Page (G-7): the entry becomes a page embed (style survives), and a
 *  markdown tile's backing `.md` trashes recoverably. The embedded page itself is
 *  never touched — the entry only references it. */
export async function convertTileToPage(root: string, host: BlockHostRef, tileId: string, pageId: string): Promise<void> {
  let wasMarkdown = false
  await mutateDoc(root, host, (cur) => {
    const blocks = Array.isArray(cur.blocks) ? cur.blocks : []
    const next = blocks.map((b) => {
      const entry = knownBlock(b)
      if (entry?.id !== tileId) return b
      if (entry.type === 'markdown') wasMarkdown = true
      const style = entry.style
      return style ? { id: tileId, type: 'page', page_id: pageId, style } : { id: tileId, type: 'page', page_id: pageId }
    })
    return { ...cur, blocks: next }
  })
  if (wasMarkdown) {
    const file = blockFilePath(root, host, tileId)
    if (await pathExists(file)) await trashWithTimestamp(root, file)
  }
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
