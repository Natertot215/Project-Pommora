import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { mkdtemp, rm, mkdir, writeFile, readFile, readdir, chmod } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { handleMutate, type MutateDeps } from './mutate'
import { openSession, closeSession } from './session'
import { closeSessionIndex } from './sessionIndex'
import { splitFrontmatter, readNexus } from './readNexus'
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

  it('movePage with order persists the destination page_order (same-parent reorder, no file move)', async () => {
    const r = await handleMutate({ op: 'movePage', path: 'Notes/Daily/Beta.md', newParentPath: 'Notes/Daily', order: ['b', 'a'] }, nexusDeps)
    expect(r.ok).toBe(true)
    expect(await pathExists(join(root, 'Notes/Daily/Beta.md'))).toBe(true)
    expect(JSON.parse(await read('Notes/Daily/_pagecollection.json')).page_order).toEqual(['b', 'a'])
  })

  it('movePage with order reparents the file AND seeds the destination page_order', async () => {
    const r = await handleMutate({ op: 'movePage', path: 'Notes/Daily/Beta.md', newParentPath: 'Notes', order: ['b'] }, nexusDeps)
    expect(r.ok).toBe(true)
    expect(await pathExists(join(root, 'Notes/Beta.md'))).toBe(true)
    expect(await pathExists(join(root, 'Notes/Daily/Beta.md'))).toBe(false)
    expect(JSON.parse(await read('Notes/_pagetype.json')).page_order).toEqual(['b'])
  })

  it('round-trip: in-collection reorder writes page_order to a Swift-era sidecar AND readNexus applies it', async () => {
    // Replicate the real on-disk shape: a Swift-era collection sidecar with views/type_id and
    // NO page_order, plus a third page.
    await writeFile(
      join(root, 'Notes', 'Daily', '_pagecollection.json'),
      JSON.stringify({ id: 'col', type_id: 'pt', schema_version: 0, modified_at: '2026-05-24T22:00:44Z', views: [{ id: 'v1', type: 'table' }] })
    )
    await writeFile(join(root, 'Notes', 'Daily', 'Gamma.md'), '---\nid: g\n---\n\nbody')
    const r = await handleMutate({ op: 'movePage', path: 'Notes/Daily/Gamma.md', newParentPath: 'Notes/Daily', order: ['g', 'b', 'a'] }, nexusDeps)
    expect(r.ok).toBe(true)
    // page_order written; views/type_id preserved (loose sidecar); file not moved
    const sc = JSON.parse(await read('Notes/Daily/_pagecollection.json'))
    expect(sc.page_order).toEqual(['g', 'b', 'a'])
    expect(sc.views).toHaveLength(1)
    expect(sc.type_id).toBe('pt')
    expect(await pathExists(join(root, 'Notes/Daily/Gamma.md'))).toBe(true)
    // readNexus applies it: Daily's pages come back in the persisted order
    const tree = await readNexus(root)
    const daily = tree.vaults.flatMap((v) => v.collections).find((c) => c.title === 'Daily')
    expect(daily?.pages.map((p) => p.id)).toEqual(['g', 'b', 'a'])
  })

  it('reorderChildren persists collection_order on the vault sidecar', async () => {
    await mkdir(join(root, 'Notes', 'Weekly'), { recursive: true })
    await writeFile(join(root, 'Notes', 'Weekly', '_pagecollection.json'), JSON.stringify({ id: 'wk' }))
    const r = await handleMutate({ op: 'reorderChildren', parentPath: 'Notes', key: 'collection_order', order: ['wk', 'col'] }, nexusDeps)
    expect(r.ok).toBe(true)
    expect(JSON.parse(await read('Notes/_pagetype.json')).collection_order).toEqual(['wk', 'col'])
  })

  it('reorderTop persists vault_order to .nexus/state.json', async () => {
    const r = await handleMutate({ op: 'reorderTop', key: 'vault_order', order: ['v2', 'v1'] }, nexusDeps)
    expect(r.ok).toBe(true)
    expect(JSON.parse(await read('.nexus/state.json')).vault_order).toEqual(['v2', 'v1'])
  })

  it('moveSet relocates a set folder (with its pages) to another collection AND writes the destination set_order', async () => {
    await mkdir(join(root, 'Notes', 'Daily', 'SetX'), { recursive: true })
    await writeFile(join(root, 'Notes', 'Daily', 'SetX', '_pageset.json'), JSON.stringify({ id: 'sx' }))
    await writeFile(join(root, 'Notes', 'Daily', 'SetX', 'Inner.md'), '---\nid: in\n---\n\nbody')
    await mkdir(join(root, 'Notes', 'Weekly'), { recursive: true })
    await writeFile(join(root, 'Notes', 'Weekly', '_pagecollection.json'), JSON.stringify({ id: 'wk' }))
    const r = await handleMutate({ op: 'moveSet', path: 'Notes/Daily/SetX', newParentPath: 'Notes/Weekly', order: ['sx'] }, nexusDeps)
    expect(r.ok).toBe(true)
    expect(await pathExists(join(root, 'Notes/Weekly/SetX/_pageset.json'))).toBe(true) // folder moved
    expect(await pathExists(join(root, 'Notes/Weekly/SetX/Inner.md'))).toBe(true) // its pages travel with it
    expect(await pathExists(join(root, 'Notes/Daily/SetX'))).toBe(false) // gone from the source collection
    expect(JSON.parse(await read('Notes/Weekly/_pagecollection.json')).set_order).toEqual(['sx'])
    const tree = await readNexus(root)
    const weekly = tree.vaults.flatMap((v) => v.collections).find((c) => c.title === 'Weekly')
    expect(weekly?.sets.map((s) => s.id)).toEqual(['sx']) // readNexus reflects the move
  })

  it('moveSet into its current collection is an in-place reorder (no folder move)', async () => {
    await mkdir(join(root, 'Notes', 'Daily', 'SetA'), { recursive: true })
    await mkdir(join(root, 'Notes', 'Daily', 'SetB'), { recursive: true })
    await writeFile(join(root, 'Notes', 'Daily', 'SetA', '_pageset.json'), JSON.stringify({ id: 'sa' }))
    await writeFile(join(root, 'Notes', 'Daily', 'SetB', '_pageset.json'), JSON.stringify({ id: 'sb' }))
    const r = await handleMutate({ op: 'moveSet', path: 'Notes/Daily/SetA', newParentPath: 'Notes/Daily', order: ['sb', 'sa'] }, nexusDeps)
    expect(r.ok).toBe(true)
    expect(await pathExists(join(root, 'Notes/Daily/SetA/_pageset.json'))).toBe(true) // stayed put
    expect(JSON.parse(await read('Notes/Daily/_pagecollection.json')).set_order).toEqual(['sb', 'sa'])
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

  it('setNexusDescription merges description into nexus.json, preserving the other keys', async () => {
    const r = await handleMutate({ op: 'setNexusDescription', description: 'A second brain.' }, nexusDeps)
    expect(r.ok).toBe(true)
    const cfg = JSON.parse(await read('.nexus/nexus.json'))
    expect(cfg.description).toBe('A second brain.')
    expect(cfg.id).toBe('nx') // existing keys untouched
    expect(cfg.schemaVersion).toBe(1)
  })

  it('setNexusDescription on a missing nexus.json starts from a minted id', async () => {
    await rm(join(root, '.nexus', 'nexus.json'), { force: true })
    const r = await handleMutate({ op: 'setNexusDescription', description: 'Fresh.' }, nexusDeps)
    expect(r.ok).toBe(true)
    const cfg = JSON.parse(await read('.nexus/nexus.json'))
    expect(cfg.description).toBe('Fresh.')
    expect(typeof cfg.id).toBe('string')
    expect(cfg.id.length).toBeGreaterThan(0)
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

describe('handleMutate — setBanner', () => {
  const PNG =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='

  it('writes a fresh-named asset under .nexus/assets/<id>/ + records it on the vault sidecar (foreign keys kept)', async () => {
    const r = await handleMutate({ op: 'setBanner', path: 'Notes', kind: 'pageType', dataUrl: PNG }, nexusDeps)
    expect(r.ok).toBe(true)
    const sc = JSON.parse(await read('Notes/_pagetype.json'))
    expect(sc.banner).toMatch(/^\.nexus\/assets\/pt\/banner-[a-z0-9]+\.png$/)
    expect(await pathExists(join(root, sc.banner))).toBe(true)
    expect(sc.id).toBe('pt') // existing keys untouched
  })

  it('sets a banner on a context (area) sidecar, keyed by the context id', async () => {
    const r = await handleMutate({ op: 'setBanner', path: '.nexus/areas/Work', kind: 'area', dataUrl: PNG }, nexusDeps)
    expect(r.ok).toBe(true)
    const sc = JSON.parse(await read('.nexus/areas/Work/_area.json'))
    expect(sc.banner).toMatch(/^\.nexus\/assets\/area-1\/banner-[a-z0-9]+\.png$/)
    expect(await pathExists(join(root, sc.banner))).toBe(true)
  })

  it('sets a banner on a collection sidecar, keyed by the collection id', async () => {
    const r = await handleMutate({ op: 'setBanner', path: 'Notes/Daily', kind: 'collection', dataUrl: PNG }, nexusDeps)
    expect(r.ok).toBe(true)
    const sc = JSON.parse(await read('Notes/Daily/_pagecollection.json'))
    expect(sc.banner).toMatch(/^\.nexus\/assets\/col\/banner-[a-z0-9]+\.png$/)
    expect(await pathExists(join(root, sc.banner))).toBe(true)
  })

  it('readNexus surfaces the banner path on vault + context + collection nodes', async () => {
    await handleMutate({ op: 'setBanner', path: 'Notes', kind: 'pageType', dataUrl: PNG }, nexusDeps)
    await handleMutate({ op: 'setBanner', path: '.nexus/areas/Work', kind: 'area', dataUrl: PNG }, nexusDeps)
    await handleMutate({ op: 'setBanner', path: 'Notes/Daily', kind: 'collection', dataUrl: PNG }, nexusDeps)
    const tree = await readNexus(root)
    expect(tree.vaults.find((v) => v.id === 'pt')?.banner).toMatch(/^\.nexus\/assets\/pt\/banner-/)
    expect(tree.contexts.areas.find((a) => a.id === 'area-1')?.banner).toMatch(/^\.nexus\/assets\/area-1\/banner-/)
    expect(tree.vaults.flatMap((v) => v.collections).find((c) => c.id === 'col')?.banner).toMatch(/^\.nexus\/assets\/col\/banner-/)
  })

  it('clearing (dataUrl null) removes the field and deletes the file', async () => {
    await handleMutate({ op: 'setBanner', path: 'Notes', kind: 'pageType', dataUrl: PNG }, nexusDeps)
    const file = JSON.parse(await read('Notes/_pagetype.json')).banner
    const r = await handleMutate({ op: 'setBanner', path: 'Notes', kind: 'pageType', dataUrl: null }, nexusDeps)
    expect(r.ok).toBe(true)
    expect(await pathExists(join(root, file))).toBe(false)
    expect(JSON.parse(await read('Notes/_pagetype.json')).banner).toBeUndefined()
  })

  it('replacing yields a NEW filename (cache-bust) and deletes the prior file', async () => {
    await handleMutate({ op: 'setBanner', path: 'Notes', kind: 'pageType', dataUrl: PNG }, nexusDeps)
    const first = JSON.parse(await read('Notes/_pagetype.json')).banner
    await handleMutate({ op: 'setBanner', path: 'Notes', kind: 'pageType', dataUrl: PNG }, nexusDeps)
    const second = JSON.parse(await read('Notes/_pagetype.json')).banner
    expect(second).not.toBe(first) // distinct URL so the renderer refetches the new image
    expect(await pathExists(join(root, first))).toBe(false) // prior deleted
    expect(await pathExists(join(root, second))).toBe(true)
  })

  it('sets a page banner as the `cover` frontmatter key, asset keyed by page id; clearing reverts', async () => {
    const created = await handleMutate({ op: 'createPage', parentPath: 'Notes/Daily', name: 'Cover' }, nexusDeps)
    expect(created.ok).toBe(true)
    if (!created.ok) return
    const pagePath = created.created!.path
    const r = await handleMutate({ op: 'setBanner', path: pagePath, kind: 'page', dataUrl: PNG }, nexusDeps)
    expect(r.ok).toBe(true)
    const after = await read(pagePath)
    const id = /id:\s*(\S+)/.exec(after)?.[1]
    const cover = /cover:\s*(\S+)/.exec(after)?.[1]
    expect(cover).toBe(`.nexus/assets/${id}/${cover?.split('/').pop()}`)
    expect(cover).toMatch(/banner-[a-z0-9]+\.png$/)
    expect(await pathExists(join(root, cover!))).toBe(true)
    // clearing removes the cover key + deletes the asset
    const cleared = await handleMutate({ op: 'setBanner', path: pagePath, kind: 'page', dataUrl: null }, nexusDeps)
    expect(cleared.ok).toBe(true)
    expect(await read(pagePath)).not.toMatch(/cover:/)
    expect(await pathExists(join(root, cover!))).toBe(false)
  })

  it('sets a homepage banner in .nexus/homepage.json keyed by "homepage"', async () => {
    const r = await handleMutate({ op: 'setBanner', path: '', kind: 'homepage', dataUrl: PNG }, nexusDeps)
    expect(r.ok).toBe(true)
    const sc = JSON.parse(await read('.nexus/homepage.json'))
    expect(sc.banner).toMatch(/^\.nexus\/assets\/homepage\/banner-[a-z0-9]+\.png$/)
    expect(await pathExists(join(root, sc.banner))).toBe(true)
    const tree = await readNexus(root)
    expect(tree.homepage.banner).toBe(sc.banner)
  })
})
