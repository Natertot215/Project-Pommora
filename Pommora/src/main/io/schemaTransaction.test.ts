import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile, writeFile, readdir } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { SchemaTransaction } from './schemaTransaction'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-txn-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const siblings = async (): Promise<string[]> =>
  (await readdir(root)).filter((n) => n.includes('.txn-') || n.includes('.bak-'))

describe('SchemaTransaction', () => {
  it('commits multiple files atomically, overwriting an existing target', async () => {
    const a = join(root, 'a.json')
    const b = join(root, 'b.md')
    await writeFile(a, 'OLD', 'utf8')

    const tx = new SchemaTransaction()
    tx.stage(a, 'NEW')
    tx.stage(b, 'fresh')
    expect(tx.size).toBe(2)
    await tx.commit()

    expect(await readFile(a, 'utf8')).toBe('NEW')
    expect(await readFile(b, 'utf8')).toBe('fresh')
    expect(await siblings()).toEqual([]) // no leftover temps/backups
    expect(tx.size).toBe(0) // pending cleared (reusable)
  })

  it('rolls back and leaves existing files untouched when staging fails', async () => {
    const a = join(root, 'a.json')
    await writeFile(a, 'KEEP', 'utf8')

    const tx = new SchemaTransaction()
    tx.stage(a, 'WOULD-CHANGE')
    tx.stage(join(root, 'missing-dir', 'b.json'), 'never') // parent dir absent → temp write fails

    await expect(tx.commit()).rejects.toThrow(/stage failed/)
    expect(await readFile(a, 'utf8')).toBe('KEEP') // original intact
    expect(await siblings()).toEqual([]) // staged temp cleaned up
  })

  it('sweeps stale .txn- temps but preserves .bak- backups for recovery', async () => {
    await writeFile(join(root, 'a.json.txn-OLD'), 'junk', 'utf8')
    await writeFile(join(root, 'a.json.bak-OLD'), 'recoverable original', 'utf8')

    const tx = new SchemaTransaction()
    tx.stage(join(root, 'a.json'), 'clean')
    await tx.commit()

    const left = await siblings()
    expect(left.some((n) => n.includes('.txn-'))).toBe(false) // uncommitted temp swept
    expect(left).toContain('a.json.bak-OLD') // recovery backup left intact
    expect(await readFile(join(root, 'a.json'), 'utf8')).toBe('clean')
  })

  it('applies last-stage-wins for a restaged target', async () => {
    const a = join(root, 'a.json')
    const tx = new SchemaTransaction()
    tx.stage(a, 'first')
    tx.stage(a, 'second')
    expect(tx.size).toBe(1)
    await tx.commit()
    expect(await readFile(a, 'utf8')).toBe('second')
  })
})
