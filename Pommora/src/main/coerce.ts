// Small read-layer coercion helpers shared by the nexus walk (readNexus) and the
// single-page read (readPage). Pure value→value; no I/O.

/** A non-empty string, or undefined. */
export function asString(v: unknown): string | undefined {
  return typeof v === 'string' && v.length > 0 ? v : undefined
}

/** An array of strings, or undefined. */
export function asStringArray(v: unknown): string[] | undefined {
  return Array.isArray(v) && v.every((x) => typeof x === 'string') ? (v as string[]) : undefined
}

/** A basename with a trailing `.md` removed (filename = title). */
export function basenameNoMd(name: string): string {
  return name.replace(/\.md$/i, '')
}
