// On-demand single-page read for the detail view.
// Reuses splitFrontmatter from the nexus walk; adds body extraction
// (everything after the closing fence). Read-only — never opens for writing.

import { readFile } from 'node:fs/promises'
import { basename, join } from 'node:path'
import type { PageDetail } from '@shared/types'
import { splitFrontmatter } from './readNexus'
import { adoptedId } from './ids'

function basenameNoMd(name: string): string {
  return name.replace(/\.md$/i, '')
}

function asString(v: unknown): string | undefined {
  return typeof v === 'string' && v.length > 0 ? v : undefined
}

/** Body = file content after the closing frontmatter fence (lenient, mirrors the split). */
function splitBody(content: string): string {
  if (!content.startsWith('---')) return content
  const m = content.match(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/)
  if (!m) return content // opening fence with no close -> whole file is body
  return content.slice(m[0].length)
}

/**
 * Read one page's full content. `relPath` is nexus-relative POSIX (as carried on
 * PageNode.path); `rootPath` is the nexus root. Callers must validate `relPath`
 * stays under root before invoking (the IPC layer does this).
 */
export async function readPage(rootPath: string, relPath: string): Promise<PageDetail> {
  const absFile = join(rootPath, relPath)
  const content = await readFile(absFile, 'utf8')
  const frontmatter = splitFrontmatter(content)
  return {
    id: asString(frontmatter.id) ?? adoptedId(relPath),
    title: basenameNoMd(basename(relPath)),
    path: relPath,
    frontmatter,
    body: splitBody(content)
  }
}
