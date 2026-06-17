import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { mkdtemp, rm, mkdir, writeFile, readFile, readdir, chmod } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { handleMutate, type MutateDeps } from './mutate'
import { openSession, closeSession } from './session'
import { closeSessionIndex } from './sessionIndex'
import { splitFrontmatter } from './readNexus'
import { pathExists } from './io/atomicWrite'

let root: string
const nexusDeps: MutateDeps = { trashMode: 'nexus', trashToSystem: async () => {} }

const read = async (rel: string): Promise<string> => readFile(join(root, rel), 'utf8')

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-mutate-'))
  await mkdir(join(root, '.nexus', 'areas', 'Work'), { recursive: true })
  await mkdir(join(root, 'Notes', 'Daily'), { recursive: true })
  await writeFile(join(root, '.nexus', 'nexus.json'), JSON.stringify({ schemaVersion: 1, id: 'nx', createdAt: '2026' }))
  await writeFile(join(root, '.nexus', 'settings.json'), '{}')
  await writeFile(join(root, '.nexus', 'areas', 'Work', '_area.json'), JSON.stringify({ id: 'area-1' }))
  await writeFile(join(root, 'Notes', '_pagetype.json'), JSON.stringify({ id: 'pt' }))
  await writeFile(join(root, 'Notes', 'Daily', '_pagecollection.json'), JSON.stringify({ id: 'col' }))
  await writeFile(join(root, 'Notes', 'Daily', 'Alpha.md'), '---\nid: a\ntier1:\n  - area-1\n---\n\nSee [[Beta]] for more.')
  await writeFile(join(root, 'Notes', 'Daily', 'Beta.md'), '---\nid: b\n---\n\nbody')
  openSession(root)
})
afterEach(async () => {
  closeSessionIndex()
  closeSession()
  await rm(root, { recursive: true, force: true })
})

describe('handleMutate — create', () => {
  it('createPage writes a .md in the resolved container + returns its relative path', async () => {
    const r = await handleMutate({ op: 'createPage', parentPath: 'Notes/Daily', name: 'New' }, nexusDeps)
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.created?.path).toBe('Notes/Daily/New.md')
    expect(await pathExists(join(root, 'Notes/Daily/New.md'))).toBe(true)
  })

  it('createContainer makes a collection folder + sidecar', async () => {
    const r = await handleMutate({ op: 'createContainer', parentPath: 'Notes', kind: 'collection', name: 'Weekly' }, nexusDeps)
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.created?.path).toBe('Notes/Weekly')
    expect(await pathExists(join(root, 'Notes/Weekly/_pagecollection.json'))).toBe(true)
  })

  it('createContext makes a tier folder under .nexus + returns its path', async () => {
    const r = await handleMutate({ op: 'createContext', tier: 1, name: 'Personal' }, nexusDeps)
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.created?.path).toBe('.nexus/areas/Personal')
    expect(await pathExists(join(root, '.nexus/areas/Personal/_area.json'))).toBe(true)
  })

  it('disambiguates a colliding create name (Untitled → Untitled 2)', async () => {
    const first = await handleMutate({ op: 'createPage', parentPath: 'Notes/Daily', name: 'Untitled' }, nexusDeps)
    const second = await handleMutate({ op: 'createPage', parentPath: 'Notes/Daily', name: 'Untitled' }, nexusDeps)
    expect(first.ok && first.created?.path).toBe('Notes/Daily/Untitled.md')
    expect(second.ok && second.created?.path).toBe('Notes/Daily/Untitled 2.md')
    expect(await pathExists(join(root, 'Notes/Daily/Untitled 2.md'))).toBe(true)
  })
})

describe('handleMutate — rename', () => {
  it('page rename renames the file AND cascades inbound [[links]]', async () => {
    const r = await handleMutate({ op: 'rename', path: 'Notes/Daily/Beta.md', kind: 'page', newName: 'Gamma' }, nexusDeps)
    expect(r.ok).toBe(true)
    expect(await pathExists(join(root, 'Notes/Daily/Gamma.md'))).toBe(true)
    expect(await pathExists(join(root, 'Notes/Daily/Beta.md'))).toBe(false)
    expect(await read('Notes/Daily/Alpha.md')).toContain('[[Gamma]]')
  })

  it('container rename renames the folder (no cascade)', async () => {
    const r = await handleMutate({ op: 'rename', path: 'Notes/Daily', kind: 'collection', newName: 'Journal' }, nexusDeps)
    expect(r.ok).toBe(true)
    expect(await pathExists(join(root, 'Notes/Journal/_pagecollection.json'))).toBe(true)
    expect(await pathExists(join(root, 'Notes/Daily'))).toBe(false)
  })

  it('rejects a duplicate name', async () => {
    const r = await handleMutate({ op: 'rename', path: 'Notes/Daily/Beta.md', kind: 'page', newName: 'Alpha' }, nexusDeps)
    expect(r.ok).toBe(false)
    if (r.ok) return
    expect(r.error.code).toBe('exists')
  })
})

describe('handleMutate — delete', () => {
  it('nexus mode moves a page to the in-nexus .trash', async () => {
    const r = await handleMutate({ op: 'delete', path: 'Notes/Daily/Beta.md', kind: 'page' }, nexusDeps)
    expect(r.ok).toBe(true)
    expect(await pathExists(join(root, 'Notes/Daily/Beta.md'))).toBe(false)
    const trashed = await readdir(join(root, '.trash'))
    expect(trashed.some((f) => f.endsWith('Beta.md'))).toBe(true)
  })

  it('system mode delegates to the injected OS-trash fn (not the .trash)', async () => {
    const trashToSystem = vi.fn(async (_p: string) => {})
    const r = await handleMutate({ op: 'delete', path: 'Notes/Daily/Beta.md', kind: 'page' }, { trashMode: 'system', trashToSystem })
    expect(r.ok).toBe(true)
    expect(trashToSystem).toHaveBeenCalledOnce()
    expect(trashToSystem.mock.calls[0][0]).toContain('Beta.md')
  })

  it('context delete strips its id from page tiers (unlinkTier) before removing the folder', async () => {
    const r = await handleMutate({ op: 'delete', path: '.nexus/areas/Work', kind: 'area' }, nexusDeps)
    expect(r.ok).toBe(true)
    expect(await pathExists(join(root, '.nexus/areas/Work'))).toBe(false)
    expect(splitFrontmatter(await read('Notes/Daily/Alpha.md')).tier1).toEqual([])
  })
})

describe('handleMutate — move + guards', () => {
  it('movePage relocates the file to another container', async () => {
    await mkdir(join(root, 'Notes', 'Archive'), { recursive: true })
    await writeFile(join(root, 'Notes', 'Archive', '_pagecollection.json'), JSON.stringify({ id: 'arc' }))
    const r = await handleMutate({ op: 'movePage', path: 'Notes/Daily/Beta.md', newParentPath: 'Notes/Archive' }, nexusDeps)
    expect(r.ok).toBe(true)
    expect(await pathExists(join(root, 'Notes/Archive/Beta.md'))).toBe(true)
    expect(await pathExists(join(root, 'Notes/Daily/Beta.md'))).toBe(false)
  })

  it('rejects a path that escapes the nexus root', async () => {
    const r = await handleMutate({ op: 'rename', path: '../evil', kind: 'page', newName: 'x' }, nexusDeps)
    expect(r.ok).toBe(false)
    if (r.ok) return
    expect(r.error.code).toBe('invalid-path')
  })

  it('fails when no nexus is open', async () => {
    closeSession()
    const r = await handleMutate({ op: 'createPage', parentPath: 'Notes', name: 'X' }, nexusDeps)
    expect(r.ok).toBe(false)
    if (r.ok) return
    expect(r.error.code).toBe('operation-failed')
  })
})

describe('handleMutate — review-round hardening', () => {
  it('createContext supports tiers 2 and 3 (topics / projects)', async () => {
    const t = await handleMutate({ op: 'createContext', tier: 2, name: 'Fitness' }, nexusDeps)
    const p = await handleMutate({ op: 'createContext', tier: 3, name: 'Launch' }, nexusDeps)
    expect(t.ok && t.created?.path).toBe('.nexus/topics/Fitness')
    expect(p.ok && p.created?.path).toBe('.nexus/projects/Launch')
    expect(await pathExists(join(root, '.nexus/topics/Fitness/_topic.json'))).toBe(true)
    expect(await pathExists(join(root, '.nexus/projects/Launch/_project.json'))).toBe(true)
  })

  it('creates a vault at the nexus root (parentPath "")', async () => {
    const r = await handleMutate({ op: 'createContainer', parentPath: '', kind: 'pageType', name: 'Inbox' }, nexusDeps)
    expect(r.ok && r.created?.path).toBe('Inbox')
    expect(await pathExists(join(root, 'Inbox/_pagetype.json'))).toBe(true)
  })

  it('refuses to delete the .nexus machinery, leaving it intact', async () => {
    const r = await handleMutate({ op: 'delete', path: '.nexus', kind: 'pageType' }, nexusDeps)
    expect(r.ok).toBe(false)
    expect(await pathExists(join(root, '.nexus'))).toBe(true)
  })

  it('rejects a name containing a NUL byte as invalid-name (not a throw)', async () => {
    const r = await handleMutate({ op: 'createPage', parentPath: 'Notes/Daily', name: 'bad' + String.fromCharCode(0) + 'name' }, nexusDeps)
    expect(r.ok).toBe(false)
    if (r.ok) return
    expect(r.error.code).toBe('invalid-name')
  })

  it('rename to the current name is a no-op success', async () => {
    const r = await handleMutate({ op: 'rename', path: 'Notes/Daily/Beta.md', kind: 'page', newName: 'Beta' }, nexusDeps)
    expect(r.ok).toBe(true)
    expect(await pathExists(join(root, 'Notes/Daily/Beta.md'))).toBe(true)
  })

  it('delete of an already-gone path returns not-found (no throw)', async () => {
    await handleMutate({ op: 'delete', path: 'Notes/Daily/Beta.md', kind: 'page' }, nexusDeps)
    const again = await handleMutate({ op: 'delete', path: 'Notes/Daily/Beta.md', kind: 'page' }, nexusDeps)
    expect(again.ok).toBe(false)
    if (again.ok) return
    expect(again.error.code).toBe('not-found')
  })

  it('movePage into the current folder is a no-op success; a name collision fails + leaves the source', async () => {
    const noop = await handleMutate({ op: 'movePage', path: 'Notes/Daily/Beta.md', newParentPath: 'Notes/Daily' }, nexusDeps)
    expect(noop.ok).toBe(true)
    expect(await pathExists(join(root, 'Notes/Daily/Beta.md'))).toBe(true)
    await mkdir(join(root, 'Notes', 'Other'), { recursive: true })
    await writeFile(join(root, 'Notes', 'Other', '_pagecollection.json'), JSON.stringify({ id: 'oth' }))
    await writeFile(join(root, 'Notes', 'Other', 'Beta.md'), '---\nid: b2\n---\n')
    const clash = await handleMutate({ op: 'movePage', path: 'Notes/Daily/Beta.md', newParentPath: 'Notes/Other' }, nexusDeps)
    expect(clash.ok).toBe(false)
    if (clash.ok) return
    expect(clash.error.code).toBe('exists')
    expect(await pathExists(join(root, 'Notes/Daily/Beta.md'))).toBe(true)
  })

  it('a malformed op returns a clean fault, not a throw', async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const r = await handleMutate({ op: 'bogus' } as any, nexusDeps)
    expect(r.ok).toBe(false)
    if (r.ok) return
    expect(r.error.code).toBe('operation-failed')
  })

  it('system-trash delete of a context strips tiers (unlinkTier) then delegates to the OS trash', async () => {
    const trashToSystem = vi.fn(async (_p: string) => {})
    const r = await handleMutate({ op: 'delete', path: '.nexus/areas/Work', kind: 'area' }, { trashMode: 'system', trashToSystem })
    expect(r.ok).toBe(true)
    expect(trashToSystem).toHaveBeenCalledOnce()
    expect(trashToSystem.mock.calls[0][0]).toContain('Work')
    expect(splitFrontmatter(await read('Notes/Daily/Alpha.md')).tier1).toEqual([])
  })

  it('reverts the page rename when the link cascade fails', async () => {
    // A page linking [[Beta]] in a read-only dir → the cascade's rewrite commit throws.
    await mkdir(join(root, 'Notes', 'Locked'), { recursive: true })
    await writeFile(join(root, 'Notes', 'Locked', '_pagecollection.json'), JSON.stringify({ id: 'lk' }))
    await writeFile(join(root, 'Notes', 'Locked', 'Linker.md'), '---\nid: lk1\n---\n\nSee [[Beta]].')
    await chmod(join(root, 'Notes', 'Locked'), 0o555)
    try {
      const r = await handleMutate({ op: 'rename', path: 'Notes/Daily/Beta.md', kind: 'page', newName: 'Gamma' }, nexusDeps)
      expect(r.ok).toBe(false)
      expect(await pathExists(join(root, 'Notes/Daily/Beta.md'))).toBe(true) // reverted
      expect(await pathExists(join(root, 'Notes/Daily/Gamma.md'))).toBe(false)
    } finally {
      await chmod(join(root, 'Notes', 'Locked'), 0o755) // restore so afterEach cleanup works
    }
  })
})
