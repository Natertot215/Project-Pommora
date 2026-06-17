import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, mkdir, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { sessionDb, openSessionIndex, closeSessionIndex } from './sessionIndex'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-sessidx-'))
  await mkdir(join(root, '.nexus'), { recursive: true })
  await mkdir(join(root, 'Notes'), { recursive: true })
  await writeFile(join(root, '.nexus', 'nexus.json'), JSON.stringify({ schemaVersion: 1, id: 'nx', createdAt: '2026' }))
  await writeFile(join(root, '.nexus', 'settings.json'), '{}')
  await writeFile(join(root, 'Notes', '_pagetype.json'), JSON.stringify({ id: 'pt' }))
  await writeFile(join(root, 'Notes', 'Hello.md'), '---\nid: pg1\n---\n\nbody')
})
afterEach(async () => {
  closeSessionIndex()
  await rm(root, { recursive: true, force: true })
})

describe('sessionIndex', () => {
  it('opens + cold-builds the index, exposing a live handle populated from the files', async () => {
    expect(sessionDb()).toBeNull()
    await openSessionIndex(root)
    const db = sessionDb()
    if (!db) throw new Error('expected a live index handle')
    const row = db.prepare('SELECT title FROM pages WHERE id = ?').get('pg1') as { title: string } | undefined
    expect(row?.title).toBe('Hello')
  })

  it('closeSessionIndex drops the handle', async () => {
    await openSessionIndex(root)
    expect(sessionDb()).not.toBeNull()
    closeSessionIndex()
    expect(sessionDb()).toBeNull()
  })

  it('reopening replaces the prior handle (session switch)', async () => {
    await openSessionIndex(root)
    expect(sessionDb()).not.toBeNull()
    await openSessionIndex(root) // index.db now exists + is current → reused, not rebuilt
    expect(sessionDb()).not.toBeNull()
  })
})
