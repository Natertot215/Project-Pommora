// Path-based kind authority: a folder's kind = which `_*.json` sidecar it carries
// (extension and frontmatter are non-authoritative). Reuses the single SIDECAR_FILENAME
// map from paths.ts — no duplicate filename list.
//
// DEVIATION FROM SWIFT (enhancement): kind is resolved by a stateless fs probe, not
// by an @Observable manager singleton holding decoded sidecars — no injection graph,
// no SIGTRAP-on-missing-injection footgun.

import { join } from 'node:path'
import { SIDECAR_FILENAME, type SidecarKind } from './paths'
import { pathExists } from './io/atomicWrite'

const KINDS = Object.keys(SIDECAR_FILENAME) as SidecarKind[]

/** The folder's kind by sidecar presence, or null for an un-adopted/raw folder. */
export async function resolveKind(absFolder: string): Promise<SidecarKind | null> {
  for (const kind of KINDS) {
    if (await pathExists(join(absFolder, SIDECAR_FILENAME[kind]))) return kind
  }
  return null
}
