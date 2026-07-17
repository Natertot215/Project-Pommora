import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import type { PreviewsFile } from '@shared/types'
import {
  EMPTY_PREVIEWS,
  flushPreviewsWrites,
  readPreviewsState,
  schedulePreviewsWrite,
} from './previewState'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'previews-'))
})
afterEach(() => rm(root, { recursive: true, force: true }))

const filePath = (): string => join(root, '.nexus', 'page-previews.json')
const seed = async (content: string): Promise<void> => {
  await mkdir(join(root, '.nexus'), { recursive: true })
  await writeFile(filePath(), content)
}

const page = (id: string) => ({ kind: 'page' as const, id, path: `Notes/${id}.md` })

describe('previewState — lenient read', () => {
  it('absent and corrupt sidecars read as the empty shape', async () => {
    expect(await readPreviewsState(root)).toEqual(EMPTY_PREVIEWS)
    await seed('{{{{not json')
    expect(await readPreviewsState(root)).toEqual(EMPTY_PREVIEWS)
  })

  it('drops junk tabs, clamps activeIndex, and reads an emptied record as absent', async () => {
    await seed(
      JSON.stringify({
        navSet: { tabs: [{ target: { kind: 'navwindow' } }], activeIndex: 99 },
        origins: {
          x: { tabs: [{ target: page('x') }, { target: 'junk' }, 42], activeIndex: -3 },
          bad: { tabs: [{ target: { kind: 'collection', id: 'c' } }], activeIndex: 0 },
        },
        open: { flavor: 'page', originId: 'x', extra: true },
      }),
    )
    const f = await readPreviewsState(root)
    expect(f.navSet).toEqual({ tabs: [{ target: { kind: 'navwindow' } }], activeIndex: 0 })
    expect(f.origins).toEqual({ x: { tabs: [{ target: page('x') }], activeIndex: 0 } })
    expect(f.open).toEqual({ flavor: 'page', originId: 'x' })
  })
})

describe('previewState — the debounced write', () => {
  it('round-trips the whole file (origins keys intact) via the drain', async () => {
    const file: PreviewsFile = {
      navSet: { tabs: [{ target: { kind: 'navwindow' } }, { target: page('n') }], activeIndex: 1 },
      origins: {
        x: { tabs: [{ target: page('x') }, { target: page('y') }], activeIndex: 0 },
        y: { tabs: [{ target: page('y') }], activeIndex: 0 },
      },
      open: { flavor: 'page', originId: 'x' },
    }
    schedulePreviewsWrite(root, file)
    await flushPreviewsWrites()
    expect(JSON.parse(await readFile(filePath(), 'utf8'))).toEqual(file)
    expect(await readPreviewsState(root)).toEqual(file)
  })

  it('a re-keyed write replaces the retired origin on disk (H-6)', async () => {
    const before: PreviewsFile = {
      navSet: null,
      origins: { x: { tabs: [{ target: page('x') }, { target: page('y') }], activeIndex: 0 } },
      open: { flavor: 'page', originId: 'x' },
    }
    schedulePreviewsWrite(root, before)
    const after: PreviewsFile = {
      navSet: null,
      origins: { y: { tabs: [{ target: page('y') }], activeIndex: 0 } },
      open: { flavor: 'page', originId: 'y' },
    }
    schedulePreviewsWrite(root, after)
    await flushPreviewsWrites()
    expect(await readPreviewsState(root)).toEqual(after)
  })
})
