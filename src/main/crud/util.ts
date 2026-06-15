// Shared helpers for the CRUD layer — the one home for the small primitives every
// mutation needs, so they aren't re-implemented per file. `pathExists` is re-exported
// from the io layer (its real owner); name + timestamp rules live here.

export { pathExists } from '../io/atomicWrite'

/** A name usable as a file/folder basename (filename = title). Rejects path separators,
 *  dot dirs, and a trailing managed extension (which the writers append themselves — a name
 *  like "Note.md" would otherwise yield "Note.md.md", breaking the filename = title invariant).
 *  Single source for the rule across page + folder + agenda CRUD. */
export function invalidName(name: string): boolean {
  const trimmed = name.trim()
  return (
    !trimmed ||
    name.includes('/') ||
    name.includes('\\') ||
    name === '.' ||
    name === '..' ||
    /\.(md|task\.json|event\.json)$/i.test(trimmed)
  )
}

/** The ISO-8601 timestamp written to governance fields (`created_at` / `modified_at`). */
export function nowIso(): string {
  return new Date().toISOString()
}
