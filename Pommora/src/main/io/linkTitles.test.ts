import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile, writeFile, mkdir } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { readLinkTitles, persistLinkTitles } from './linkTitles'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-linktitles-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const storeFile = (r: string): string => join(r, '.nexus', 'linkTitles.json')

describe('link-title cache (.nexus/linkTitles.json)', () => {
  it('reads empty when the file is absent', async () => {
    expect(await readLinkTitles(root)).toEqual({})
  })

  it('round-trips a URL → title map', async () => {
    const cache = { 'https://example.com': 'Example Domain', 'https://rust-lang.org': 'Rust' }
    await persistLinkTitles(root, cache)
    expect(await readLinkTitles(root)).toEqual(cache)
  })

  it('persists to .nexus/linkTitles.json (a device-local, regeneratable cache)', async () => {
    await persistLinkTitles(root, { 'https://x.com': 'X' })
    expect(JSON.parse(await readFile(storeFile(root), 'utf8'))).toEqual({ 'https://x.com': 'X' })
  })

  it('drops non-string and empty-string entries on read', async () => {
    await mkdir(join(root, '.nexus'), { recursive: true })
    await writeFile(
      storeFile(root),
      JSON.stringify({ 'https://ok.com': 'Good', 'https://num.com': 42, 'https://empty.com': '' })
    )
    expect(await readLinkTitles(root)).toEqual({ 'https://ok.com': 'Good' })
  })

  it('reads empty on a corrupt file', async () => {
    await mkdir(join(root, '.nexus'), { recursive: true })
    await writeFile(storeFile(root), 'not json {')
    expect(await readLinkTitles(root)).toEqual({})
  })
})
