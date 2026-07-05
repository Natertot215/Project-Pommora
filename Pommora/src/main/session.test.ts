import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtempSync, rmSync, writeFileSync, realpathSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { sessionRoot, openSession, closeSession, resolveRestorePath } from './session'

describe('session — open/close', () => {
  beforeEach(() => closeSession())

  it('starts empty', () => {
    expect(sessionRoot()).toBeNull()
  })

  it('opens then closes', async () => {
    await openSession('/Users/x/Nexus')
    expect(sessionRoot()).toBe('/Users/x/Nexus') // non-existent → falls back to the raw path
    closeSession()
    expect(sessionRoot()).toBeNull()
  })

  it('canonicalizes the root via realpath (so its lock key matches resolveUnderRoot)', async () => {
    const raw = mkdtempSync(join(tmpdir(), 'pom-sess-')) // macOS: /var/… symlinks to /private/var/…
    await openSession(raw)
    expect(sessionRoot()).toBe(realpathSync(raw))
    closeSession()
    rmSync(raw, { recursive: true, force: true })
  })
})

describe('resolveRestorePath', () => {
  let dir: string
  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'pom-sess-'))
  })
  afterEach(() => {
    rmSync(dir, { recursive: true, force: true })
  })

  it('restores a readable directory', async () => {
    expect(await resolveRestorePath({ lastNexusPath: dir })).toBe(dir)
  })

  it('returns null when no path is persisted', async () => {
    expect(await resolveRestorePath({})).toBeNull()
  })

  it('returns null when the path no longer exists', async () => {
    expect(await resolveRestorePath({ lastNexusPath: join(dir, 'gone') })).toBeNull()
  })

  it('returns null when the path is a file, not a directory', async () => {
    const file = join(dir, 'a-file.md')
    writeFileSync(file, 'x')
    expect(await resolveRestorePath({ lastNexusPath: file })).toBeNull()
  })
})
