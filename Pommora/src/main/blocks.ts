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

/** The block document lives in the host's CONTENT dir (`_blocks.json` beside the
 *  block `.md` files) — the watcher ignores that dir, so a layout gesture never
 *  costs a nexus re-walk. `homepage.json` (watched — the tree reads its banner)
 *  holds no block keys. */
export function blockHostConfig(root: string, host: BlockHostRef): string {
  return join(blockHostDir(root, host), '_blocks.json')
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
  await mkdir(blockHostDir(root, host), { recursive: true })
  await serializeOnFile(path, () => mutateJson<Record<string, unknown>>(path, () => ({}), fn))
}

/** One-time migration: earlier builds kept the doc on homepage.json — lift those
 *  keys into the sidecar and strip them, so the watched file never carries block
 *  churn again. No-op once the sidecar exists. */
async function migrateLegacyDoc(root: string, host: BlockHostRef): Promise<void> {
  if (host.kind !== 'homepage' || (await pathExists(blockHostConfig(root, host)))) return
  const legacyPath = nexusConfig(root, NEXUS_CONFIG_FILES.homepage)
  const legacy = await readJsonObject(legacyPath)
  if (!legacy || !('layout' in legacy || 'blocks' in legacy || 'blocks_locked' in legacy)) return
  await mutateDoc(root, host, (cur) => ({
    ...cur,
    ...('layout' in legacy ? { layout: legacy.layout } : {}),
    ...('blocks' in legacy ? { blocks: legacy.blocks } : {}),
    ...('blocks_locked' in legacy ? { blocks_locked: legacy.blocks_locked } : {})
  }))
  await serializeOnFile(legacyPath, () =>
    mutateJson<Record<string, unknown>>(
      legacyPath,
      () => ({}),
      (cur) => {
        const next = { ...cur }
        delete next.layout
        delete next.blocks
        delete next.blocks_locked
        return next
      }
    )
  )
}

export async function readBlockDoc(root: string, host: BlockHostRef): Promise<BlockDoc> {
  await migrateLegacyDoc(root, host)
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
    // On the FILE lock — orders against a still-pending editor flush, so a late
    // body write can never land after the trash and resurrect the file.
    await serializeOnFile(file, async () => {
      if (await pathExists(file)) await trashWithTimestamp(root, file)
    })
  }
}

/** Turn Into → Page (G-7): the entry becomes a page embed (foreign fields + chrome
 *  payload survive the flip), and a markdown tile's backing `.md` trashes
 *  recoverably. The embedded page itself is never touched. */
export async function convertTileToPage(root: string, host: BlockHostRef, tileId: string, pageId: string): Promise<void> {
  let wasMarkdown = false
  await mutateDoc(root, host, (cur) => {
    const blocks = Array.isArray(cur.blocks) ? cur.blocks : []
    const next = blocks.map((b) => {
      const entry = knownBlock(b)
      if (entry?.id !== tileId) return b
      if (entry.type === 'markdown') wasMarkdown = true
      // Spread the RAW entry — foreign keys and chrome payload survive the
      // type flip (E-1); only the type + target change.
      return { ...(b as Record<string, unknown>), type: 'page', page_id: pageId }
    })
    return { ...cur, blocks: next }
  })
  if (wasMarkdown) {
    const file = blockFilePath(root, host, tileId)
    // On the FILE lock — orders against a still-pending editor flush, so a late
    // body write can never land after the trash and resurrect the file.
    await serializeOnFile(file, async () => {
      if (await pathExists(file)) await trashWithTimestamp(root, file)
    })
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
