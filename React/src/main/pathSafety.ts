// The single path-safety validator every read and write funnels through. The
// renderer only ever sends nexus-relative POSIX paths/ids; main resolves them
// under the open nexus root and rejects anything that escapes it.
//
// Three rejections: an absolute input, a `..` traversal, and — the one the prior
// resolve()/relative()-only guard in page:open missed — a symlink INSIDE the
// nexus that resolves to a target OUTSIDE it. realpath both sides closes that
// hole: a contained-looking lexical path whose real target sits outside the root
// is caught after the links collapse.

import { isAbsolute, relative, resolve, sep } from 'node:path'
import { realpath } from 'node:fs/promises'
import { fail, ok, type Result } from '@shared/result'

/** True when `rel` (a `path.relative` result) climbs out of its base. */
function escapes(rel: string): boolean {
  return rel === '..' || rel.startsWith('..' + sep) || isAbsolute(rel)
}

/**
 * Resolve an EXISTING nexus-relative path under `root`, fully symlink-safe.
 * Returns the canonical absolute path on success.
 *
 * realpath requires the path to exist, so a missing target is `not-found`, not a
 * security reject. Callers that CREATE a new entity validate the existing PARENT
 * directory through this, then `join` an `invalidName`-checked basename onto the
 * returned (canonical, contained) parent — the new path is then safe by
 * construction without needing to realpath a path that doesn't exist yet.
 */
export async function resolveUnderRoot(root: string, relPath: unknown): Promise<Result<string>> {
  if (typeof relPath !== 'string' || relPath.length === 0) {
    return fail('invalid-path', 'A path is required.')
  }
  if (isAbsolute(relPath)) {
    return fail('invalid-path', 'Absolute paths are not allowed.')
  }
  // Fast lexical reject (no fs touch) for an obvious `..` climb.
  if (escapes(relative(resolve(root), resolve(root, relPath)))) {
    return fail('invalid-path', 'Path escapes the nexus root.')
  }
  // Canonicalize both sides so an in-nexus symlink can't smuggle the target out.
  let realRoot: string
  let realTarget: string
  try {
    realRoot = await realpath(resolve(root))
    realTarget = await realpath(resolve(root, relPath))
  } catch {
    return fail('not-found', 'Path not found.')
  }
  const rel = relative(realRoot, realTarget)
  if (rel !== '' && escapes(rel)) {
    return fail('invalid-path', 'Path escapes the nexus root.')
  }
  return ok(realTarget)
}
