// On-demand single-page read for the detail view.
// Reuses splitFrontmatter from the nexus walk; adds body extraction
// (everything after the closing fence). Read-only — never opens for writing.

import { readFile } from 'node:fs/promises'
import { basename, join } from 'node:path'
import type { PageDetail } from '@shared/types'
import { splitFrontmatter } from './readNexus'
import { splitEnvelope } from './io/pageFile'
import { asString, basenameNoMd } from './coerce'
import { adoptedId } from './ids'

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
    body: splitEnvelope(content).body,
  }
}
