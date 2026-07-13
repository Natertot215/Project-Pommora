import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, mkdir, writeFile, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { ensureSettings, readDefaultViewScale, updateSettings } from './settings'
import { nexusDir, nexusConfig, NEXUS_CONFIG_FILES } from './paths'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-settings-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const path = () => nexusConfig(root, NEXUS_CONFIG_FILES.settings)
const readSettings = async (): Promise<Record<string, unknown>> => JSON.parse(await readFile(path(), 'utf8'))
const write = async (v: object): Promise<void> => {
  await mkdir(nexusDir(root), { recursive: true })
  await writeFile(path(), JSON.stringify(v))
}

// The on-disk settings shape our writer must always produce: version + modified_at + full labels,
// every label a {singular, plural} LabelPair (all three tiers now first-class).
const assertFullSettings = (s: Record<string, unknown>): void => {
  expect(typeof s.version).toBe('number')
  expect(typeof s.modified_at).toBe('string')
  expect(s.modified_at).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/) // iso8601, no ms
  const labels = s.labels as Record<string, unknown>
  for (const k of ['area', 'topic', 'project', 'page_collection', 'page_set', 'agenda_task', 'agenda_event']) {
    const pair = labels[k] as Record<string, unknown>
    expect(typeof pair.singular).toBe('string')
    expect(typeof pair.plural).toBe('string')
  }
}

describe('ensureSettings', () => {
  it('writes a full Swift-decodable seed when absent', async () => {
    await ensureSettings(root)
    assertFullSettings(await readSettings())
  })

  it('backfills a partial settings.json (only profile_image) without dropping it', async () => {
    await write({ profile_image: '.nexus/assets/x/profile-a.png' })
    await ensureSettings(root)
    const s = await readSettings()
    assertFullSettings(s)
    expect(s.profile_image).toBe('.nexus/assets/x/profile-a.png') // preserved
  })

  it('leaves a complete file byte-identical (no churn on re-open)', async () => {
    await ensureSettings(root) // seed once → complete
    const before = await readFile(path(), 'utf8')
    await ensureSettings(root) // second pass
    expect(await readFile(path(), 'utf8')).toBe(before)
  })
})

describe('updateSettings — serialized RMW (G-1)', () => {
  it('concurrent writes to different keys never clobber', async () => {
    await ensureSettings(root)
    // Fired together: unserialized read-modify-writes each merge onto the SAME stale snapshot and
    // the last write wins, dropping the others. serializeOnFile forces them to queue, so all land.
    await Promise.all([
      updateSettings(root, (c) => ({ ...c, a: 1 })),
      updateSettings(root, (c) => ({ ...c, b: 2 })),
      updateSettings(root, (c) => ({ ...c, c: 3 })),
      updateSettings(root, (c) => ({ ...c, d: 4 }))
    ])
    const s = await readSettings()
    expect([s.a, s.b, s.c, s.d]).toEqual([1, 2, 3, 4])
    assertFullSettings(s) // the seed keys survived the concurrent writes too
  })
})

describe('readDefaultViewScale', () => {
  it('defaults to 1.0 when the file or the key is absent', async () => {
    expect(await readDefaultViewScale(root)).toBe(1) // no settings.json at all
    await write({ personalization: {} })
    expect(await readDefaultViewScale(root)).toBe(1) // present, key absent
  })

  it('returns a valid in-range scale', async () => {
    await write({ personalization: { defaultViewScale: 1.25 } })
    expect(await readDefaultViewScale(root)).toBe(1.25)
  })

  it('clamps out-of-range values so a typo cannot brick the window', async () => {
    await write({ personalization: { defaultViewScale: 125 } })
    expect(await readDefaultViewScale(root)).toBe(3) // MAX
    await write({ personalization: { defaultViewScale: 0.1 } })
    expect(await readDefaultViewScale(root)).toBe(0.5) // MIN
  })

  it('falls back to 1.0 on a non-numeric or malformed value', async () => {
    await write({ personalization: { defaultViewScale: 'big' } })
    expect(await readDefaultViewScale(root)).toBe(1)
    await write({ personalization: 'nope' })
    expect(await readDefaultViewScale(root)).toBe(1)
  })
})
