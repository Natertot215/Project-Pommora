// PropertyValue — the type-erased on-disk value used in Page/Agenda `properties`.
// The DECLARED type lives in the schema; this codec recovers a value from raw JSON
// by SHAPE, in a LOCKED precedence that mirrors the Swift original exactly. The
// order is load-bearing and silent on failure — reordering a branch mistypes
// relations/files/multi-select with no error. Pure: no fs, no Node — importable by
// both main and renderer.

/** On-disk file-attachment shape (snake_case = the on-disk DTO). Round-trips as-is;
 *  unknown keys on a file object are preserved (the codec passes the object through). */
export interface FileRef {
  path: string
  original_name?: string
  added_at?: string
  mime_type?: string
}

export type PropertyValue =
  | { kind: 'number'; value: number }
  | { kind: 'checkbox'; value: boolean }
  | { kind: 'date'; value: string } // "yyyy-MM-dd" (UTC)
  | { kind: 'datetime'; value: string } // full ISO-8601 with timezone
  | { kind: 'select'; value: string }
  | { kind: 'multiSelect'; value: string[] }
  | { kind: 'status'; value: string }
  | { kind: 'relation'; value: string[] } // target ULIDs
  | { kind: 'url'; value: string }
  | { kind: 'file'; value: FileRef[] }
  | { kind: 'lastEditedTime' } // virtual — never persisted (encode throws)
  | { kind: 'null' }

// RFC-3986 scheme prefix — matches Swift's `URL(string:).scheme != nil`.
const SCHEME = /^[a-zA-Z][a-zA-Z0-9+.-]*:/
const YMD = /^\d{4}-\d{2}-\d{2}$/
// ISO-8601 with time + timezone designator — matches Swift's `.withInternetDateTime`
// (no fractional seconds; a TZ is required, else the string falls through to select).
const ISO_DATETIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:\d{2})$/

/** True for a plain (non-null, non-array) object. The one shared shape guard for JSON /
 *  frontmatter records across the data layer. */
export function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v)
}

function isFileRef(v: unknown): v is FileRef {
  return isPlainObject(v) && typeof v.path === 'string'
}

/**
 * Classify a raw JSON value into a PropertyValue. BRANCH ORDER IS LOAD-BEARING —
 * mirrors Swift `PropertyValue.init(from:)`:
 * null → bool → number → non-empty [{$rel}] → non-empty [FileRef] → [string]
 * (incl. empty [] → multiSelect([])) → single {$rel}/{$status} →
 * string(url → iso-datetime → yyyy-MM-dd → select). Anything else throws.
 */
export function parsePropertyValue(raw: unknown): PropertyValue {
  if (raw === null || raw === undefined) return { kind: 'null' }
  if (typeof raw === 'boolean') return { kind: 'checkbox', value: raw }
  if (typeof raw === 'number') return { kind: 'number', value: raw }

  if (Array.isArray(raw)) {
    if (raw.length > 0 && raw.every((x) => isPlainObject(x) && typeof x.$rel === 'string')) {
      return { kind: 'relation', value: raw.map((x) => (x as { $rel: string }).$rel) }
    }
    if (raw.length > 0 && raw.every(isFileRef)) {
      return { kind: 'file', value: raw }
    }
    if (raw.every((x) => typeof x === 'string')) {
      // Includes the empty array: `[]` → multiSelect([]) (Swift's [String] branch
      // catches it before the dead file([]) path).
      return { kind: 'multiSelect', value: raw as string[] }
    }
    throw new Error('PropertyValue: unrecognised array shape')
  }

  if (isPlainObject(raw)) {
    const keys = Object.keys(raw)
    if (keys.length === 1) {
      if (typeof raw.$rel === 'string') return { kind: 'relation', value: [raw.$rel] }
      if (typeof raw.$status === 'string') return { kind: 'status', value: raw.$status }
    }
  }

  if (typeof raw === 'string') {
    if (SCHEME.test(raw)) return { kind: 'url', value: raw }
    if (ISO_DATETIME.test(raw)) return { kind: 'datetime', value: raw }
    if (YMD.test(raw)) return { kind: 'date', value: raw }
    return { kind: 'select', value: raw }
  }

  throw new Error('PropertyValue: unrecognised JSON shape')
}

/** Encode a PropertyValue to its on-disk JSON value. The switch is exhaustive (the
 *  compiler enforces every case). `lastEditedTime` is virtual and throws. */
export function encodePropertyValue(value: PropertyValue): unknown {
  switch (value.kind) {
    case 'number':
      return value.value
    case 'checkbox':
      return value.value
    case 'select':
      return value.value
    case 'url':
      return value.value
    case 'date':
      return value.value
    case 'datetime':
      return value.value
    case 'multiSelect':
      return value.value
    case 'status':
      return { $status: value.value }
    case 'relation':
      return value.value.map((id) => ({ $rel: id }))
    case 'file':
      return value.value
    case 'null':
      return null
    case 'lastEditedTime':
      throw new Error(
        'PropertyValue.lastEditedTime is virtual and must not be persisted; derive from modified_at at read time.'
      )
  }
}

/** Set or clear one property on a (possibly malformed) properties record, returning the next
 *  record. A null value (or the `null` kind) clears the key; anything else encodes via the
 *  codec. The single owner of the page + agenda property set/clear rule. */
export function applyPropertyValue(
  current: unknown,
  propertyId: string,
  value: PropertyValue | null
): Record<string, unknown> {
  const next: Record<string, unknown> = isPlainObject(current) ? { ...current } : {}
  if (value === null || value.kind === 'null') delete next[propertyId]
  else next[propertyId] = encodePropertyValue(value)
  return next
}
