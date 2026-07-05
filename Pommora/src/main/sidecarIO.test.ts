import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { readSidecar, writeSidecar } from './sidecarIO'
import { SIDECAR_FILENAME } from './paths'
import { pageCollectionSidecar } from '@shared/schemas'

let dir: string
beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), 'pom-sidecar-'))
})
afterEach(async () => {
  await rm(dir, { recursive: true, force: true })
})

describe('sidecar read/write', () => {
  it('round-trips a sidecar through write then read', async () => {
    await writeSidecar(dir, 'collection', { id: 'T1', icon: 'box', page_order: ['p1'] })
    expect(await readSidecar(dir, 'collection', pageCollectionSidecar)).toMatchObject({
      id: 'T1',
      icon: 'box',
      page_order: ['p1']
    })
  })

  it('preserves foreign keys across write + read (Swift dropped these)', async () => {
    await writeSidecar(dir, 'collection', { id: 'T1', plugin: 'keep', meta: { v: 2 } })
    const back = await readSidecar(dir, 'collection', pageCollectionSidecar)
    expect(back).toMatchObject({ id: 'T1', plugin: 'keep', meta: { v: 2 } })
  })

  it('writes sorted, stable JSON with a trailing newline', async () => {
    await writeSidecar(dir, 'collection', { id: 'T1', icon: 'box' })
    const text = await readFile(join(dir, SIDECAR_FILENAME.collection), 'utf8')
    expect(text).toBe('{\n  "icon": "box",\n  "id": "T1"\n}\n')
  })

  it('returns null for a missing sidecar', async () => {
    expect(await readSidecar(dir, 'collection', pageCollectionSidecar)).toBeNull()
  })

  it('returns null for an invalid sidecar (missing id)', async () => {
    await writeSidecar(dir, 'collection', { icon: 'no-id' })
    expect(await readSidecar(dir, 'collection', pageCollectionSidecar)).toBeNull()
  })
})
