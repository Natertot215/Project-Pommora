import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtempSync, rmSync, writeFileSync, realpathSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  sessionRoot,
  openSession,
  closeSession,
  resolveRestorePath,
  isTrashedPath,
  pruneRecents,
} from './session'

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

describe('isTrashedPath', () => {
  it('flags system + volume + in-nexus trash segments (case-insensitive)', () => {
    expect(isTrashedPath('/Users/x/.Trash/OldNexus')).toBe(true)
    expect(isTrashedPath('/Volumes/Drive/.Trashes/501/Nexus')).toBe(true)
    expect(isTrashedPath('/Users/x/Nexus/Coll/.trash/Page')).toBe(true)
  })
  it('passes a live path with no trash segment', () => {
    expect(isTrashedPath('/Users/x/The Nexus')).toBe(false)
  })
})

describe('pruneRecents', () => {
  let dir: string
  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'pom-rec-'))
  })
  afterEach(() => {
    rmSync(dir, { recursive: true, force: true })
  })

  it('drops a deleted nexus (gone path) while keeping live ones, order preserved', async () => {
    const live = mkdtempSync(join(tmpdir(), 'pom-live-'))
    const gone = join(dir, 'deleted-nexus')
    expect(await pruneRecents([dir, gone, live])).toEqual([dir, live])
    rmSync(live, { recursive: true, force: true })
  })

  it('drops an entry that resolves into the trash even if it exists', async () => {
    const trashed = join(dir, '.Trash', 'Nexus')
    mkdtempSync(join(tmpdir(), 'pom-x-')) // noise
    expect(await pruneRecents([trashed])).toEqual([])
  })

  it('returns [] for an empty list', async () => {
    expect(await pruneRecents([])).toEqual([])
  })
})
