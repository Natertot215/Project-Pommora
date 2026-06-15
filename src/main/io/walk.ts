// Recursive `.md` enumeration for mutation cascades (delete-property strips, rename
// cascades, tier unlinks). This is the simple "find the files to rewrite" walk — distinct
// from readNexus, which builds the typed tree with exclusions, depth caps, and adoption.

import { readdir } from 'node:fs/promises'
import { join } from 'node:path'

/** Every `.md` file under `dir` (recursive), as absolute paths. `skipTopLevel` drops
 *  entries whose first path segment matches (e.g. `['.nexus', '.trash']` for a nexus-wide
 *  walk). A missing/unreadable dir yields []. */
export async function listMarkdownFiles(
  dir: string,
  opts: { skipTopLevel?: string[] } = {}
): Promise<string[]> {
  let rels: string[]
  try {
    rels = await readdir(dir, { recursive: true })
  } catch {
    return []
  }
  const skip = new Set(opts.skipTopLevel ?? [])
  return rels
    .filter((r) => r.endsWith('.md'))
    .filter((r) => !skip.has(r.split(/[/\\]/)[0]))
    .map((r) => join(dir, r))
}

/** Files directly in `dir` (non-recursive) whose name ends with `suffix`, as absolute
 *  paths. Used for flat agenda folders (`.task.json` / `.event.json` items). */
export async function listFilesBySuffix(dir: string, suffix: string): Promise<string[]> {
  let names: string[]
  try {
    names = await readdir(dir)
  } catch {
    return []
  }
  return names.filter((n) => n.endsWith(suffix)).map((n) => join(dir, n))
}
