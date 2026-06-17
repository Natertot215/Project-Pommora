import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, existsSync } from 'node:fs'
import { tmpdir, homedir } from 'node:os'
import { join } from 'node:path'
import { readNexus, splitFrontmatter } from './readNexus'

const d = (p: string): void => {
  mkdirSync(p, { recursive: true })
}
const w = (p: string, c = ''): void => {
  writeFileSync(p, c)
}

let raw: string
let sidecar: string

beforeAll(() => {
  // --- raw / un-adopted nexus (the ~/test shape: no .nexus, no sidecars) ---
  raw = mkdtempSync(join(tmpdir(), 'pom-raw-'))
  d(join(raw, 'Vault A', 'Collection A'))
  w(join(raw, 'Vault A', 'Collection A', 'Page A.md'), '---\nid: page-a\nicon: star\n---\n\nbody')
  w(join(raw, 'Vault A', 'Collection A', 'Page B.md'), 'no frontmatter, just body')
  w(join(raw, 'Vault A', 'Root Page.md'), '# hi')
  d(join(raw, 'Vault B'))
  d(join(raw, '_internal'))
  w(join(raw, '_internal', 'x.md'), 'should be skipped')
  d(join(raw, 'Tasks'))
  w(join(raw, 'Tasks', 't.md'), 'agenda — hidden')

  // --- sidecar-driven nexus ---
  sidecar = mkdtempSync(join(tmpdir(), 'pom-sc-'))
  d(join(sidecar, '.nexus', 'areas', 'Work'))
  w(join(sidecar, '.nexus', 'nexus.json'), JSON.stringify({ schemaVersion: 1, id: 'nx1', createdAt: '2026' }))
  w(join(sidecar, '.nexus', 'settings.json'), JSON.stringify({ excluded_folders: ['Archive'] }))
  w(join(sidecar, '.nexus', 'areas', 'Work', '_area.json'), JSON.stringify({ id: 'area-work', color: 'blue' }))
  d(join(sidecar, 'Notes', 'Daily'))
  w(join(sidecar, 'Notes', '_pagetype.json'), JSON.stringify({ id: 'pt-notes' }))
  w(join(sidecar, 'Notes', 'Daily', '_pagecollection.json'), JSON.stringify({ id: 'col-daily' }))
  w(join(sidecar, 'Notes', 'Daily', 'Entry.md'), '---\nid: e1\n---\n')
  w(join(sidecar, 'Notes', 'Loose.md'), 'vault-root page')
  d(join(sidecar, 'Archive'))
  w(join(sidecar, 'Archive', '_pagetype.json'), JSON.stringify({ id: 'pt-arch' }))
  d(join(sidecar, 'PlainFolder')) // no sidecar -> not a pageType in sidecar mode
})

afterAll(() => {
  rmSync(raw, { recursive: true, force: true })
  rmSync(sidecar, { recursive: true, force: true })
})

describe('splitFrontmatter', () => {
  it('parses fenced frontmatter', () => {
    expect(splitFrontmatter('---\nid: x\n---\nbody')).toEqual({ id: 'x' })
  })
  it('returns empty for no fence', () => {
    expect(splitFrontmatter('# just markdown')).toEqual({})
  })
  it('returns empty for unterminated fence', () => {
    expect(splitFrontmatter('---\nid: x\nno close')).toEqual({})
  })
})

describe('readNexus — structure mode (raw, like ~/test)', () => {
  it('classifies vaults/collections/pages; hides agenda + internal', async () => {
    const t = await readNexus(raw)
    expect(t.vaults.map((v) => v.title)).toEqual(['Vault A', 'Vault B']) // title fallback order
    const a = t.vaults.find((v) => v.title === 'Vault A')!
    expect(a.collections.map((c) => c.title)).toEqual(['Collection A'])
    expect(a.pages.map((p) => p.title)).toEqual(['Root Page'])
    expect(a.collections[0].pages.map((p) => p.title)).toEqual(['Page A', 'Page B'])
    expect(t.vaults.find((v) => v.title === 'Tasks')).toBeUndefined()
    expect(t.vaults.find((v) => v.title === '_internal')).toBeUndefined()
    expect(t.contexts.areas.length).toBe(0)
  })

  it('synthesizes stable adopted ids across reads', async () => {
    const t1 = await readNexus(raw)
    const t2 = await readNexus(raw)
    expect(t1.vaults[0].id).toBe(t2.vaults[0].id)
    expect(t1.vaults[0].id.startsWith('adopted-')).toBe(true)
  })

  it('reads frontmatter id+icon; adopts no-frontmatter pages', async () => {
    const t = await readNexus(raw)
    const ca = t.vaults.find((v) => v.title === 'Vault A')!.collections[0]
    const pa = ca.pages.find((p) => p.title === 'Page A')!
    const pb = ca.pages.find((p) => p.title === 'Page B')!
    expect(pa.id).toBe('page-a')
    expect(pa.icon).toBe('star')
    expect(pa.path).toBe('Vault A/Collection A/Page A.md')
    expect(pb.id.startsWith('adopted-')).toBe(true)
  })
})

describe('readNexus — sidecar mode', () => {
  it('gates on sidecars, applies exclusion, reads area color', async () => {
    const t = await readNexus(sidecar)
    expect(t.nexus.id).toBe('nx1')
    expect(t.vaults.map((v) => v.title)).toEqual(['Notes']) // Archive excluded; PlainFolder has no sidecar
    const notes = t.vaults[0]
    expect(notes.collections.map((c) => c.title)).toEqual(['Daily'])
    expect(notes.pages.map((p) => p.title)).toEqual(['Loose'])
    expect(notes.collections[0].pages.map((p) => p.title)).toEqual(['Entry'])
    expect(t.contexts.areas[0]?.color).toBe('blue')
  })
})

describe('readNexus — real test nexus (optional smoke)', () => {
  const real = process.env.TEST_NEXUS_PATH || join(homedir(), 'test')
  it.runIf(existsSync(real))('reads the real nexus without throwing', async () => {
    const t = await readNexus(real)
    expect(Array.isArray(t.vaults)).toBe(true)
  })
})

describe('readNexus — accent setting', () => {
  const roots: string[] = []
  const mk = (settings: object): string => {
    const root = mkdtempSync(join(tmpdir(), 'pom-accent-'))
    roots.push(root)
    d(join(root, '.nexus'))
    w(join(root, '.nexus', 'nexus.json'), JSON.stringify({ schemaVersion: 1, id: 'nxa', createdAt: '2026' }))
    w(join(root, '.nexus', 'settings.json'), JSON.stringify(settings))
    return root
  }
  afterAll(() => roots.forEach((r) => rmSync(r, { recursive: true, force: true })))

  it('reads a valid spectrum accent', async () => {
    expect((await readNexus(mk({ accent: 'blue' }))).accent).toBe('blue')
  })
  it('passes through system', async () => {
    expect((await readNexus(mk({ accent: 'system' }))).accent).toBe('system')
  })
  it('defaults when the accent is invalid', async () => {
    expect((await readNexus(mk({ accent: 'chartreuse' }))).accent).toBe('lavender')
  })
  it('defaults when the accent is absent', async () => {
    expect((await readNexus(mk({}))).accent).toBe('lavender')
  })
})

describe('readNexus — container paths (nexus-relative, for mutation addressing)', () => {
  let root: string
  beforeAll(() => {
    root = mkdtempSync(join(tmpdir(), 'pom-paths-'))
    // Contexts (one per tier, under .nexus/<tier>/).
    d(join(root, '.nexus', 'areas', 'Work'))
    d(join(root, '.nexus', 'topics', 'Health'))
    d(join(root, '.nexus', 'projects', 'Launch'))
    // Type -> Collection -> Set -> Page.
    d(join(root, 'Notes', 'Daily', 'Morning'))
    w(join(root, '.nexus', 'nexus.json'), JSON.stringify({ schemaVersion: 1, id: 'nxp', createdAt: '2026' }))
    w(join(root, '.nexus', 'settings.json'), '{}')
    w(join(root, '.nexus', 'areas', 'Work', '_area.json'), JSON.stringify({ id: 'a1' }))
    w(join(root, '.nexus', 'topics', 'Health', '_topic.json'), JSON.stringify({ id: 't1' }))
    w(join(root, '.nexus', 'projects', 'Launch', '_project.json'), JSON.stringify({ id: 'p1' }))
    w(join(root, 'Notes', '_pagetype.json'), JSON.stringify({ id: 'pt1' }))
    w(join(root, 'Notes', 'Daily', '_pagecollection.json'), JSON.stringify({ id: 'c1' }))
    w(join(root, 'Notes', 'Daily', 'Morning', '_pageset.json'), JSON.stringify({ id: 's1' }))
    w(join(root, 'Notes', 'Daily', 'Morning', 'Entry.md'), '---\nid: e1\n---\n')
  })
  afterAll(() => rmSync(root, { recursive: true, force: true }))

  it('carries each container + context path, POSIX-relative to the root', async () => {
    const t = await readNexus(root)
    expect(t.contexts.areas[0].path).toBe('.nexus/areas/Work')
    expect(t.contexts.topics[0].path).toBe('.nexus/topics/Health')
    expect(t.contexts.projects[0].path).toBe('.nexus/projects/Launch')
    const notes = t.vaults[0]
    expect(notes.path).toBe('Notes')
    expect(notes.collections[0].path).toBe('Notes/Daily')
    expect(notes.collections[0].sets[0].path).toBe('Notes/Daily/Morning')
    expect(notes.collections[0].sets[0].pages[0].path).toBe('Notes/Daily/Morning/Entry.md')
  })
})
