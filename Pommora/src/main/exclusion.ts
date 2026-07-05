// One pure predicate unifying convention skips + user folder exclusions.
// Collapses what the Swift app spreads across Filesystem, IndexBuilder,
// NexusAdopter, and FolderFilter into a single testable function.

/** NFC-normalize + case-fold a single path segment for comparison. */
export function normalizeSeg(s: string): string {
  return s.normalize('NFC').toLocaleLowerCase()
}

/**
 * Should this directory be skipped while walking the nexus?
 * @param name    the directory's own name (basename)
 * @param relPath the directory path relative to the nexus root (POSIX-style, '/'-joined)
 * @param excluded user `excluded_folders` from settings.json (nexus-relative paths)
 */
export function shouldSkipDir(name: string, relPath: string, excluded: string[]): boolean {
  // Convention skips: dot-prefixed (.nexus/.git/.trash), underscore-prefixed
  // (sidecars are files, but underscore folders are internal), and node_modules.
  if (name.startsWith('.') || name.startsWith('_') || name === 'node_modules') return true

  if (!excluded.length) return false

  const rel = relPath.split('/').filter(Boolean).map(normalizeSeg)
  for (const ex of excluded) {
    const exSegs = ex.split('/').filter(Boolean).map(normalizeSeg)
    if (exSegs.length === 0) continue
    // Segment-prefix match: the excluded path is a prefix of this folder's path.
    if (exSegs.every((seg, i) => rel[i] === seg)) return true
  }
  return false
}
