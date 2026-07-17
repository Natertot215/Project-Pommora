import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, mkdir, writeFile, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { ensureIdentity } from './identity'
import { isUlid } from './ids'
import { nexusDir, nexusConfig, NEXUS_CONFIG_FILES } from './paths'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-identity-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const idPath = () => nexusConfig(root, NEXUS_CONFIG_FILES.identity)
const readId = async (): Promise<Record<string, unknown>> =>
  JSON.parse(await readFile(idPath(), 'utf8'))
const writeId = async (v: object): Promise<void> => {
  await mkdir(nexusDir(root), { recursive: true })
  await writeFile(idPath(), JSON.stringify(v))
}

describe('ensureIdentity', () => {
  it('creates nexus.json in Swift shape when absent', async () => {
    const r = await ensureIdentity(root)
    expect(r.created).toBe(true)
    const j = await readId()
    expect(j.schemaVersion).toBe(1)
    expect(typeof j.id === 'string' && isUlid(j.id as string)).toBeTruthy()
    // ISO-8601 with NO fractional seconds — Swift's .iso8601 decoder rejects milliseconds.
    expect(j.createdAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
  })

  it('backfills missing schemaVersion/createdAt without touching an existing id', async () => {
    await writeId({ id: 'existing-ulid', description: 'keep me' })
    const r = await ensureIdentity(root)
    expect(r.created).toBe(false)
    expect(r.id).toBe('existing-ulid')
    const j = await readId()
    expect(j.id).toBe('existing-ulid') // unchanged
    expect(j.schemaVersion).toBe(1) // backfilled
    expect(j.createdAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/) // backfilled
    expect(j.description).toBe('keep me') // foreign key preserved
  })

  it('leaves a complete file byte-identical (no churn on re-open)', async () => {
    await writeId({ schemaVersion: 1, id: 'nx', createdAt: '2026-06-24T20:00:00Z' })
    const before = await readFile(idPath(), 'utf8')
    const r = await ensureIdentity(root)
    expect(r.created).toBe(false)
    expect(await readFile(idPath(), 'utf8')).toBe(before) // untouched
  })
})
