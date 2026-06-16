import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, writeFile, mkdir } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { resolveKind } from './kind'
import { SIDECAR_FILENAME } from './paths'

let dir: string
beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), 'pom-kind-'))
})
afterEach(async () => {
  await rm(dir, { recursive: true, force: true })
})

async function folderWith(sidecarFile: string): Promise<string> {
  // Unique folder per sidecar so a prior call's sidecar can't leak in.
  const folder = join(dir, sidecarFile.replace(/[^a-z0-9]/gi, ''))
  await mkdir(folder, { recursive: true })
  await writeFile(join(folder, sidecarFile), '{"id":"X"}', 'utf8')
  return folder
}

describe('resolveKind', () => {
  it('resolves a page type by its sidecar', async () => {
    expect(await resolveKind(await folderWith(SIDECAR_FILENAME.pageType))).toBe('pageType')
  })

  it('resolves a context tier by its sidecar', async () => {
    expect(await resolveKind(await folderWith(SIDECAR_FILENAME.area))).toBe('area')
    expect(await resolveKind(await folderWith(SIDECAR_FILENAME.project))).toBe('project')
  })

  it('returns null for an un-adopted/raw folder (no sidecar)', async () => {
    const bare = join(dir, 'bare')
    await mkdir(bare, { recursive: true })
    expect(await resolveKind(bare)).toBeNull()
  })
})
