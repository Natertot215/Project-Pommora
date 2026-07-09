import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, existsSync } from 'node:fs'
import { tmpdir, homedir } from 'node:os'
import { join } from 'node:path'
import { readNexus, readPersonalization, splitFrontmatter } from './readNexus'

describe('readPersonalization: ribbon knobs', () => {
  it('coerces a valid sidebarMode + ribbonOrder', () => {
    const p = readPersonalization({ sidebarMode: 'agenda', ribbonOrder: ['agenda', 'collections'] })
    expect(p.sidebarMode).toBe('agenda')
    expect(p.ribbonOrder).toEqual(['agenda', 'collections'])
  })
  it('drops an invalid sidebarMode and filters garbage from ribbonOrder', () => {
    const p = readPersonalization({ sidebarMode: 'bogus', ribbonOrder: [1, '', 'contexts'] })
    expect(p.sidebarMode).toBeUndefined()
    expect(p.ribbonOrder).toEqual(['contexts'])
  })
  it('leaves both undefined when absent', () => {
    const p = readPersonalization({})
    expect(p.sidebarMode).toBeUndefined()
    expect(p.ribbonOrder).toBeUndefined()
  })
})

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
  // Agenda singleton — hidden from Collections by its CONFIG sidecar, not its name.
  d(join(raw, 'Tasks'))
  w(join(raw, 'Tasks', '_taskconfig.json'), '{}')
  w(join(raw, 'Tasks', 'Submit.task.json'), '{}')

  // --- sidecar-driven nexus (2-tier: _pagecollection.json top, recursive _pageset.json) ---
  sidecar = mkdtempSync(join(tmpdir(), 'pom-sc-'))
  d(join(sidecar, '.nexus', 'areas', 'Work'))
  w(join(sidecar, '.nexus', 'nexus.json'), JSON.stringify({ schemaVersion: 1, id: 'nx1', createdAt: '2026' }))
  w(join(sidecar, '.nexus', 'settings.json'), JSON.stringify({ excluded_folders: ['Archive'] }))
  w(join(sidecar, '.nexus', 'areas', 'Work', '_area.json'), JSON.stringify({ id: 'area-work', color: 'blue' }))
  w(
    join(sidecar, '.nexus', 'properties.json'),
    JSON.stringify({
      prop_p1: { id: 'prop_p1', name: 'Status', type: 'select', select_options: [{ value: 'a', label: 'A', color: 'blue' }] }
    })
  )
  d(join(sidecar, 'Notes', 'Daily'))
  w(join(sidecar, 'Notes', '_pagecollection.json'), JSON.stringify({ id: 'col-notes', properties: ['prop_p1'] }))
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

describe('readNexus — agenda is config-driven, never name-reserved', () => {
  const roots: string[] = []
  const mk = (build: (root: string) => void): string => {
    const root = mkdtempSync(join(tmpdir(), 'pom-agenda-'))
    roots.push(root)
    d(join(root, '.nexus'))
    w(join(root, '.nexus', 'nexus.json'), JSON.stringify({ schemaVersion: 1, id: 'nxg', createdAt: '2026' }))
    build(root)
    return root
  }
  afterAll(() => roots.forEach((r) => rmSync(r, { recursive: true, force: true })))

  it('hides a folder carrying _taskconfig/_eventconfig, whatever its name', async () => {
    const root = mk((r) => {
      d(join(r, 'My Reminders'))
      w(join(r, 'My Reminders', '_taskconfig.json'), '{}') // renamed Tasks singleton
      d(join(r, 'Real'))
      w(join(r, 'Real', '_pagecollection.json'), JSON.stringify({ id: 'c' }))
    })
    expect((await readNexus(root)).collections!.map((c) => c.title)).toEqual(['Real'])
  })

  it('shows a folder NAMED Agenda/Tasks that has a collection sidecar + no agenda config', async () => {
    const root = mk((r) => {
      d(join(r, 'Agenda'))
      w(join(r, 'Agenda', '_pagecollection.json'), JSON.stringify({ id: 'a' }))
      d(join(r, 'Tasks'))
      w(join(r, 'Tasks', '_pagecollection.json'), JSON.stringify({ id: 't' }))
    })
    // The names aren't reserved — only the agenda config sidecar hides a folder.
    expect((await readNexus(root)).collections!.map((c) => c.title).sort()).toEqual(['Agenda', 'Tasks'])
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

describe('readNexus — personalization', () => {
  const roots: string[] = []
  const mk = (settings: object): string => {
    const root = mkdtempSync(join(tmpdir(), 'pom-pers-'))
    roots.push(root)
    d(join(root, '.nexus'))
    w(join(root, '.nexus', 'nexus.json'), JSON.stringify({ schemaVersion: 1, id: 'nxp', createdAt: '2026' }))
    w(join(root, '.nexus', 'settings.json'), JSON.stringify(settings))
    return root
  }
  afterAll(() => roots.forEach((r) => rmSync(r, { recursive: true, force: true })))

  it('reads accent from personalization.accent (the new home)', async () => {
    expect((await readNexus(mk({ personalization: { accent: 'blue' } }))).accent).toBe('blue')
  })
  it('personalization.accent wins over the legacy top-level accent_color', async () => {
    expect((await readNexus(mk({ accent_color: 'red', personalization: { accent: 'blue' } }))).accent).toBe('blue')
  })
  it('reads the block, dropping invalid fields + unknown icon kinds', async () => {
    const t = await readNexus(
      mk({
        personalization: {
          connectionColor: 'cyan',
          hideChevrons: true,
          outlinerLines: 'nope', // not a boolean → dropped
          defaultIcons: { collection: 'gallery-vertical-end', bogus: 'x' }
        }
      })
    )
    expect(t.personalization.connectionColor).toBe('cyan')
    expect(t.personalization.hideChevrons).toBe(true)
    expect(t.personalization.outlinerLines).toBeUndefined()
    expect(t.personalization.defaultIcons).toEqual({ collection: 'gallery-vertical-end' })
  })
  it('absent personalization → empty block', async () => {
    const t = await readNexus(mk({}))
    expect(t.personalization.connectionColor).toBeUndefined()
    expect(t.personalization.defaultIcons).toBeUndefined()
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
    expect(t.labels.area).toEqual({ singular: 'Area', plural: 'Spaces' })
    expect(t.labels.topic).toEqual({ singular: 'Topic', plural: 'Themes' })
    expect(t.labels.pageCollection).toEqual({ singular: 'Library', plural: 'Libraries' })
    expect(t.labels.pageSet).toEqual({ singular: 'Shelf', plural: 'Shelves' })
    expect(t.labels.project).toEqual({ singular: 'Initiative', plural: 'Initiatives' })
    expect(t.labels.agendaTask).toEqual({ singular: 'Todo', plural: 'Todos' })
    expect(t.labels.agendaEvent).toEqual({ singular: 'Happening', plural: 'Happenings' })
  })

  it('reads new-shape area/topic LabelPairs directly, ignoring legacy sidebar_sections', async () => {
    const t = await readNexus(
      mk({
        labels: {
          area: { singular: 'Zone', plural: 'Zones' },
          topic: { singular: 'Theme', plural: 'Themes' },
          sidebar_sections: { areas: 'IGNORED', topics: 'IGNORED' }
        }
      })
    )
    expect(t.labels.area).toEqual({ singular: 'Zone', plural: 'Zones' })
    expect(t.labels.topic).toEqual({ singular: 'Theme', plural: 'Themes' })
  })

  it('falls back to defaults on missing keys (area/topic → Area(s)/Topic(s))', async () => {
    const t = await readNexus(mk({}))
    expect(t.labels.area).toEqual({ singular: 'Area', plural: 'Areas' })
    expect(t.labels.topic).toEqual({ singular: 'Topic', plural: 'Topics' })
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

describe('PropertiesV2 — registry-resolved collection schema', () => {
  it('resolves assignment ids to registry defs in order, dropping dangling refs', async () => {
    const root = mkdtempSync(join(tmpdir(), 'pom-readnexus-v2-'))
    d(join(root, '.nexus'))
    w(join(root, '.nexus', 'nexus.json'), JSON.stringify({ id: 'nx' }))
    w(
      join(root, '.nexus', 'properties.json'),
      JSON.stringify({
        prop_a: { id: 'prop_a', name: 'Priority', type: 'select', select_options: [{ value: 'hi', label: 'High', color: 'red' }] },
        prop_b: { id: 'prop_b', name: 'Done', type: 'checkbox' }
      })
    )
    d(join(root, 'Notes'))
    w(join(root, 'Notes', '_pagecollection.json'), JSON.stringify({ id: 'col_notes', properties: ['prop_a', 'prop_gone', 'prop_b'] }))

    const tree = await readNexus(root)
    const notes = tree.collections!.find((c) => c.id === 'col_notes')!
    expect(notes.properties?.map((p) => p.id)).toEqual(['prop_a', 'prop_b'])
    expect(notes.properties?.map((p) => p.name)).toEqual(['Priority', 'Done'])
    rmSync(root, { recursive: true, force: true })
  })
})
