// Batch frontmatter read for a container's view pipeline. Walks every `.md` under a container
// (recursive — own pages + nested Sets) and returns a `pageId → PageFrontmatter` map, keyed by the
// SAME id the read engine assigns (frontmatter.id, else adoptedId of the nexus-relative path) so it
// joins cleanly to the tree's PageNodes in flattenContainer. Read-only; lazy (called on container
// open, not woven into the tree walk).

import { readFile } from 'node:fs/promises'
import { join, relative, sep } from 'node:path'
import { pageFrontmatter, type PageFrontmatter } from '@shared/schemas'
import { splitFrontmatter } from '../readNexus'
import { adoptedId } from '../ids'
import { asString } from '../coerce'
import { listMarkdownFiles } from '../io/walk'

export async function loadValues(
  rootPath: string,
  containerRelPath: string
): Promise<Record<string, PageFrontmatter>> {
  const absFolder = join(rootPath, containerRelPath)
  const out: Record<string, PageFrontmatter> = {}
  for (const absFile of await listMarkdownFiles(absFolder)) {
    let fm: Record<string, unknown>
    try {
      fm = splitFrontmatter(await readFile(absFile, 'utf8'))
    } catch {
      continue // unreadable page → skip (its row falls back to a minimal frontmatter)
    }
    const relFile = relative(rootPath, absFile).split(sep).join('/')
    const id = asString(fm.id) ?? adoptedId(relFile)
    const parsed = pageFrontmatter.safeParse({ ...fm, id })
    if (parsed.success) out[id] = parsed.data
  }
  return out
}
