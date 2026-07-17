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
  return excludedMatcher(excluded)(relPath.split('/'))
}

/** Precompiled `excluded_folders` matcher: root-anchored, whole-segment prefix match over
 *  normalized segments. Curried so per-event callers (the watcher) compile the list once. */
export function excludedMatcher(excluded: string[]): (segs: string[]) => boolean {
  const prefixes = excluded
    .map((ex) => ex.split('/').filter(Boolean).map(normalizeSeg))
    .filter((p) => p.length > 0)
  if (prefixes.length === 0) return () => false
  return (segs) => {
    const norm = segs.filter(Boolean).map(normalizeSeg)
    return prefixes.some((p) => p.every((seg, i) => norm[i] === seg))
  }
}
