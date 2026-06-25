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
  // --- raw / un-adopted nexus (the ~/test shape: no .nexus, no sidecars). 2-tier:
  //     root folder = Collection, every subfolder = Set, recursive (no depth cap). ---
  raw = mkdtempSync(join(tmpdir(), 'pom-raw-'))
  d(join(raw, 'Collection A', 'Set A', 'Sub A'))
  w(join(raw, 'Collection A', 'Set A', 'Sub A', 'Deep.md'), '# deep (depth-3, proves no cap)')
  w(join(raw, 'Collection A', 'Set A', 'Page A.md'), '---\nid: page-a\nicon: star\n---\n\nbody')
  w(join(raw, 'Collection A', 'Set A', 'Page B.md'), 'no frontmatter, just body')
  w(join(raw, 'Collection A', 'Root Page.md'), '# collection-root page')
  d(join(raw, 'Collection B'))
  d(join(raw, '_internal'))
  w(join(raw, '_internal', 'x.md'), 'should be skipped')
  d(join(raw, 'Tasks'))
  w(join(raw, 'Tasks', 't.md'), 'agenda — hidden')

  // --- sidecar-driven nexus (2-tier: _pagecollection.json top, recursive _pageset.json) ---
  sidecar = mkdtempSync(join(tmpdir(), 'pom-sc-'))
  d(join(sidecar, '.nexus', 'areas', 'Work'))
  w(join(sidecar, '.nexus', 'nexus.json'), JSON.stringify({ schemaVersion: 1, id: 'nx1', createdAt: '2026' }))
  w(join(sidecar, '.nexus', 'settings.json'), JSON.stringify({ excluded_folders: ['Archive'] }))
  w(join(sidecar, '.nexus', 'areas', 'Work', '_area.json'), JSON.stringify({ id: 'area-work', color: 'blue' }))
  d(join(sidecar, 'Notes', 'Daily'))
  w(
    join(sidecar, 'Notes', '_pagecollection.json'),
    JSON.stringify({ id: 'col-notes', properties: [{ id: 'p1', name: 'Status', type: 'select' }] })
  )
  w(join(sidecar, 'Notes', 'Daily', '_pageset.json'), JSON.stringify({ id: 'set-daily', parent_id: 'col-notes' }))
  w(join(sidecar, 'Notes', 'Daily', 'Entry.md'), '---\nid: e1\n---\n')
  w(join(sidecar, 'Notes', 'Loose.md'), 'collection-root page')
  d(join(sidecar, 'Archive'))
  w(join(sidecar, 'Archive', '_pagecollection.json'), JSON.stringify({ id: 'col-arch' }))
  d(join(sidecar, 'PlainFolder')) // no sidecar -> not a Collection in sidecar mode
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
  it('classifies collections/sets/pages recursively; hides agenda + internal', async () => {
    const t = await readNexus(raw)
    const collections = t.collections!
    expect(collections.map((c) => c.title)).toEqual(['Collection A', 'Collection B']) // title fallback order
    const a = collections.find((c) => c.title === 'Collection A')!
    expect(a.sets.map((s) => s.title)).toEqual(['Set A'])
    expect(a.pages.map((p) => p.title)).toEqual(['Root Page'])
    const setA = a.sets[0]
    expect(setA.pages.map((p) => p.title)).toEqual(['Page A', 'Page B'])
    // depth-3 sub-set loads as a nested Set (no cap, no roll-up)
    expect(setA.sets!.map((s) => s.title)).toEqual(['Sub A'])
    expect(setA.sets![0].pages.map((p) => p.title)).toEqual(['Deep'])
    expect(collections.find((c) => c.title === 'Tasks')).toBeUndefined()
    expect(collections.find((c) => c.title === '_internal')).toBeUndefined()
    expect(t.contexts.areas.length).toBe(0)
  })

  it('synthesizes stable adopted ids across reads', async () => {
    const t1 = await readNexus(raw)
    const t2 = await readNexus(raw)
    expect(t1.collections![0].id).toBe(t2.collections![0].id)
    expect(t1.collections![0].id.startsWith('adopted-')).toBe(true)
  })

  it('reads frontmatter id+icon; adopts no-frontmatter pages', async () => {
    const t = await readNexus(raw)
    const setA = t.collections!.find((c) => c.title === 'Collection A')!.sets[0]
    const pa = setA.pages.find((p) => p.title === 'Page A')!
    const pb = setA.pages.find((p) => p.title === 'Page B')!
    expect(pa.id).toBe('page-a')
    expect(pa.icon).toBe('star')
    expect(pa.path).toBe('Collection A/Set A/Page A.md')
    expect(pb.id.startsWith('adopted-')).toBe(true)
  })
})

describe('readNexus — sidecar mode', () => {
  it('gates on _pagecollection.json, applies exclusion, reads schema + area color', async () => {
    const t = await readNexus(sidecar)
    expect(t.nexus.id).toBe('nx1')
    // Archive excluded; PlainFolder has no sidecar
    expect(t.collections!.map((c) => c.title)).toEqual(['Notes'])
    const notes = t.collections![0]
    expect(notes.sets.map((s) => s.title)).toEqual(['Daily'])
    expect(notes.pages.map((p) => p.title)).toEqual(['Loose'])
    expect(notes.sets[0].pages.map((p) => p.title)).toEqual(['Entry'])
    expect(notes.properties?.length).toBe(1)
    expect((notes.properties?.[0] as { name?: string })?.name).toBe('Status')
    expect(t.contexts.areas[0]?.color).toBe('blue')
  })
})

describe('readNexus — real test nexus (optional smoke)', () => {
  const real = process.env.TEST_NEXUS_PATH || join(homedir(), 'test')
  it.runIf(existsSync(real))('reads the real nexus without throwing', async () => {
    const t = await readNexus(real)
    expect(Array.isArray(t.collections)).toBe(true)
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

  it('reads the shared accent_color key (React-native value passes through)', async () => {
    expect((await readNexus(mk({ accent_color: 'blue' }))).accent).toBe('blue')
    expect((await readNexus(mk({ accent_color: 'lavender' }))).accent).toBe('lavender')
  })
  it('maps Swift-only accent values onto React tokens', async () => {
    expect((await readNexus(mk({ accent_color: 'gray' }))).accent).toBe('grey')
    expect((await readNexus(mk({ accent_color: 'pink' }))).accent).toBe('purple')
  })
  it('passes through system', async () => {
    expect((await readNexus(mk({ accent_color: 'system' }))).accent).toBe('system')
  })
  it('defaults when the accent is invalid', async () => {
    expect((await readNexus(mk({ accent_color: 'chartreuse' }))).accent).toBe('lavender')
  })
  it('defaults when accent_color is absent', async () => {
    expect((await readNexus(mk({}))).accent).toBe('lavender')
  })
})

describe('readNexus — structured labels (Swift SettingsLabels shape)', () => {
  const roots: string[] = []
  const mk = (settings: object): string => {
    const root = mkdtempSync(join(tmpdir(), 'pom-labels-'))
    roots.push(root)
    d(join(root, '.nexus'))
    w(join(root, '.nexus', 'nexus.json'), JSON.stringify({ schemaVersion: 1, id: 'nxl', createdAt: '2026' }))
    w(join(root, '.nexus', 'settings.json'), JSON.stringify(settings))
    return root
  }
  afterAll(() => roots.forEach((r) => rmSync(r, { recursive: true, force: true })))

  it('parses a Swift labels blob into the structured shape', async () => {
    const t = await readNexus(
      mk({
        labels: {
          sidebar_sections: { areas: 'Spaces', topics: 'Themes', pages: 'Libraries' },
          page_collection: { singular: 'Library', plural: 'Libraries' },
          page_set: { singular: 'Shelf', plural: 'Shelves' },
          project: { singular: 'Initiative', plural: 'Initiatives' },
          agenda_task: { singular: 'Todo', plural: 'Todos' },
          agenda_event: { singular: 'Happening', plural: 'Happenings' }
        }
      })
    )
    expect(t.labels.sidebarSections).toEqual({ areas: 'Spaces', topics: 'Themes', pages: 'Libraries' })
    expect(t.labels.pageCollection).toEqual({ singular: 'Library', plural: 'Libraries' })
    expect(t.labels.pageSet).toEqual({ singular: 'Shelf', plural: 'Shelves' })
    expect(t.labels.project).toEqual({ singular: 'Initiative', plural: 'Initiatives' })
    expect(t.labels.agendaTask).toEqual({ singular: 'Todo', plural: 'Todos' })
    expect(t.labels.agendaEvent).toEqual({ singular: 'Happening', plural: 'Happenings' })
  })

  it('falls back to Swift defaults on missing keys (pages default "Collections")', async () => {
    const t = await readNexus(mk({}))
    expect(t.labels.sidebarSections).toEqual({ areas: 'Areas', topics: 'Topics', pages: 'Collections' })
    expect(t.labels.pageCollection).toEqual({ singular: 'Collection', plural: 'Collections' })
    expect(t.labels.pageSet).toEqual({ singular: 'Set', plural: 'Sets' })
    expect(t.labels.project.plural).toBe('Projects')
  })
})

describe('readNexus — saved-config items[] (Swift shape)', () => {
  const roots: string[] = []
  const mk = (savedConfig: object): string => {
    const root = mkdtempSync(join(tmpdir(), 'pom-saved-'))
    roots.push(root)
    d(join(root, '.nexus'))
    w(join(root, '.nexus', 'nexus.json'), JSON.stringify({ schemaVersion: 1, id: 'nxs', createdAt: '2026' }))
    w(join(root, '.nexus', 'saved-config.json'), JSON.stringify(savedConfig))
    return root
  }
  afterAll(() => roots.forEach((r) => rmSync(r, { recursive: true, force: true })))

  it('resolves a saved label from items[{key,label}]', async () => {
    const t = await readNexus(mk({ schemaVersion: 1, items: [{ key: 'homepage', label: 'Home' }] }))
    expect(t.saved.find((s) => s.key === 'homepage')?.title).toBe('Home')
    expect(t.saved.find((s) => s.key === 'calendar')?.title).toBe('Calendar') // default for unlisted
  })
})

describe('readNexus — profile (from settings, Swift parity)', () => {
  const roots: string[] = []
  const mk = (settings: object): string => {
    const root = mkdtempSync(join(tmpdir(), 'pom-profile-'))
    roots.push(root)
    d(join(root, '.nexus'))
    w(join(root, '.nexus', 'nexus.json'), JSON.stringify({ schemaVersion: 1, id: 'nxp', createdAt: '2026' }))
    w(join(root, '.nexus', 'settings.json'), JSON.stringify(settings))
    return root
  }
  afterAll(() => roots.forEach((r) => rmSync(r, { recursive: true, force: true })))

  it('reads profile_image (rel path) + profile_subtitle from settings', async () => {
    const t = await readNexus(mk({ profile_image: '.nexus/assets/nxp/profile-abc.png', profile_subtitle: 'Mine' }))
    expect(t.nexus.profileImage).toBe('.nexus/assets/nxp/profile-abc.png')
    expect(t.nexus.profileSubtitle).toBe('Mine')
  })

  it('defaults to null image + empty subtitle when absent', async () => {
    const t = await readNexus(mk({}))
    expect(t.nexus.profileImage).toBeNull()
    expect(t.nexus.profileSubtitle).toBe('')
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
    // Collection -> Set -> Sub-Set -> Page (recursive 2-tier).
    d(join(root, 'Notes', 'Daily', 'Morning'))
    w(join(root, '.nexus', 'nexus.json'), JSON.stringify({ schemaVersion: 1, id: 'nxp', createdAt: '2026' }))
    w(join(root, '.nexus', 'settings.json'), '{}')
    w(join(root, '.nexus', 'areas', 'Work', '_area.json'), JSON.stringify({ id: 'a1' }))
    w(join(root, '.nexus', 'topics', 'Health', '_topic.json'), JSON.stringify({ id: 't1' }))
    w(join(root, '.nexus', 'projects', 'Launch', '_project.json'), JSON.stringify({ id: 'p1' }))
    w(join(root, 'Notes', '_pagecollection.json'), JSON.stringify({ id: 'c-notes' }))
    w(join(root, 'Notes', 'Daily', '_pageset.json'), JSON.stringify({ id: 's-daily', parent_id: 'c-notes' }))
    w(join(root, 'Notes', 'Daily', 'Morning', '_pageset.json'), JSON.stringify({ id: 's-morning', parent_id: 's-daily' }))
    w(join(root, 'Notes', 'Daily', 'Morning', 'Entry.md'), '---\nid: e1\n---\n')
  })
  afterAll(() => rmSync(root, { recursive: true, force: true }))

  it('carries each container + context path, POSIX-relative to the root', async () => {
    const t = await readNexus(root)
    expect(t.contexts.areas[0].path).toBe('.nexus/areas/Work')
    expect(t.contexts.topics[0].path).toBe('.nexus/topics/Health')
    expect(t.contexts.projects[0].path).toBe('.nexus/projects/Launch')
    const notes = t.collections![0]
    expect(notes.path).toBe('Notes')
    expect(notes.sets[0].path).toBe('Notes/Daily')
    expect(notes.sets[0].sets![0].path).toBe('Notes/Daily/Morning')
    expect(notes.sets[0].sets![0].pages[0].path).toBe('Notes/Daily/Morning/Entry.md')
  })
})
