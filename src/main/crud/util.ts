// Shared helpers for the CRUD layer — the one home for the small primitives every
// mutation needs, so they aren't re-implemented per file. `pathExists` is re-exported
// from the io layer (its real owner); name + timestamp rules live here.

export { pathExists } from '../io/atomicWrite'

/** A name usable as a file/folder basename (filename = title). Rejects path separators
 *  and dot dirs. Single source for the rule across page + folder + schema CRUD. */
export function invalidName(name: string): boolean {
  return !name.trim() || name.includes('/') || name.includes('\\') || name === '.' || name === '..'
}

/** The ISO-8601 timestamp written to governance fields (`created_at` / `modified_at`). */
export function nowIso(): string {
  return new Date().toISOString()
}
