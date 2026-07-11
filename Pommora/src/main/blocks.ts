// The BlockHost read/write path (D-2): the block document lives on the host's own
// config — homepage.json for the dev host (G-12) — and every write is a locked
// read-merge-write, so layout/blocks/blocks_locked are the ONLY keys touched and
// foreign keys (banner included) survive. All homepage.json writers serialize on
// the config path: this module and setBanner's homepage branch share the lock, or
// a banner write racing a debounced layout write becomes a whole-file lost update.

import type { BlockDoc, BlockDocPatch, BlockHostRef } from '@shared/blocks'
import { mutateJson, readJsonObject } from './io/atomicWrite'
import { serializeOnFile } from './io/fileLock'
import { nexusConfig, NEXUS_CONFIG_FILES } from './paths'

export function blockHostConfig(root: string, _host: BlockHostRef): string {
  return nexusConfig(root, NEXUS_CONFIG_FILES.homepage)
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
  const path = blockHostConfig(root, host)
  await serializeOnFile(path, () =>
    mutateJson<Record<string, unknown>>(
      path,
      () => ({}),
      (cur) => {
        const next = { ...cur }
        if ('layout' in patch) next.layout = patch.layout
        if ('blocks' in patch) next.blocks = patch.blocks
        if ('locked' in patch) {
          if (patch.locked) next.blocks_locked = true
          else delete next.blocks_locked
        }
        return next
      }
    )
  )
}
