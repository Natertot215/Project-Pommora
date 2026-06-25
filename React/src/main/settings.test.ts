import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, mkdir, writeFile, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { ensureSettings } from './settings'
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

// The keys Swift's Settings/SettingsLabels decoders REQUIRE (no fallback).
const assertSwiftDecodable = (s: Record<string, unknown>): void => {
  expect(typeof s.version).toBe('number')
  expect(typeof s.modified_at).toBe('string')
  expect(s.modified_at).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/) // iso8601, no ms
  const labels = s.labels as Record<string, unknown>
  expect(labels.sidebar_sections).toBeTruthy()
  for (const k of ['project', 'agenda_task', 'agenda_event']) {
    const pair = labels[k] as Record<string, unknown>
    expect(typeof pair.singular).toBe('string')
    expect(typeof pair.plural).toBe('string')
  }
}

describe('ensureSettings', () => {
  it('writes a full Swift-decodable seed when absent', async () => {
    await ensureSettings(root)
    assertSwiftDecodable(await readSettings())
  })

  it('backfills a partial settings.json (only profile_image) without dropping it', async () => {
    await write({ profile_image: '.nexus/assets/x/profile-a.png' })
    await ensureSettings(root)
    const s = await readSettings()
    assertSwiftDecodable(s)
    expect(s.profile_image).toBe('.nexus/assets/x/profile-a.png') // preserved
  })

  it('leaves a complete file byte-identical (no churn on re-open)', async () => {
    await ensureSettings(root) // seed once → complete
    const before = await readFile(path(), 'utf8')
    await ensureSettings(root) // second pass
    expect(await readFile(path(), 'utf8')).toBe(before)
  })
})
