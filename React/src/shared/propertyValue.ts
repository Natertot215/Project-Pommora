// PropertyValue — the type-erased on-disk value used in Page/Agenda `properties`.
// The DECLARED type lives in the schema; this codec recovers a value from raw JSON
// by SHAPE, in a LOCKED precedence that mirrors the Swift original exactly. The
// order is load-bearing and silent on failure — reordering a branch mistypes
// contexts/files/multi-select with no error. Pure: no fs, no Node — importable by
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
  | { kind: 'datetime'; value: string } // ISO-8601; a bare "yyyy-MM-dd" is a date-only datetime
  | { kind: 'select'; value: string }
  | { kind: 'multiSelect'; value: string[] }
  | { kind: 'status'; value: string }
  | { kind: 'context'; value: string[] } // context-tier target ULIDs
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
 * null → bool → number → non-empty [{$ctx}] → non-empty [FileRef] → [string]
 * (incl. empty [] → multiSelect([])) → single {$ctx}/{$status} →
 * string(url → iso-datetime → yyyy-MM-dd-as-datetime → select). Anything else throws.
 */
export function parsePropertyValue(raw: unknown): PropertyValue {
  if (raw === null || raw === undefined) return { kind: 'null' }
  if (typeof raw === 'boolean') return { kind: 'checkbox', value: raw }
  if (typeof raw === 'number') return { kind: 'number', value: raw }

  if (Array.isArray(raw)) {
    if (raw.length > 0 && raw.every((x) => isPlainObject(x) && typeof x.$ctx === 'string')) {
      return { kind: 'context', value: raw.map((x) => (x as { $ctx: string }).$ctx) }
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
      if (typeof raw.$ctx === 'string') return { kind: 'context', value: [raw.$ctx] }
      if (typeof raw.$status === 'string') return { kind: 'status', value: raw.$status }
    }
  }

  if (typeof raw === 'string') {
    if (SCHEME.test(raw)) return { kind: 'url', value: raw }
    if (ISO_DATETIME.test(raw)) return { kind: 'datetime', value: raw }
    if (YMD.test(raw)) return { kind: 'datetime', value: raw } // a bare date is a date-only datetime
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
    case 'datetime':
      return value.value
    case 'multiSelect':
      return value.value
    case 'status':
      return { $status: value.value }
    case 'context':
      return value.value.map((id) => ({ $ctx: id }))
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

/** True when a value carries nothing — an empty array or empty string. Checkbox `false` and
 *  number `0` are real values and stay. */
function isEmptyValue(value: PropertyValue): boolean {
  switch (value.kind) {
    case 'multiSelect':
    case 'context':
    case 'file':
      return value.value.length === 0
    case 'select':
    case 'status':
    case 'url':
    case 'datetime':
      return value.value === ''
    default:
      return false
  }
}

/** Set or clear one property on a (possibly malformed) properties record, returning the next
 *  record. A null value (the `null` kind) OR an empty value clears the key — a page without a
 *  value has no key at all, never a null/[]/'' placeholder — anything else encodes via the
 *  codec. The single owner of the page + agenda property set/clear rule. */
export function applyPropertyValue(
  current: unknown,
  propertyId: string,
  value: PropertyValue | null
): Record<string, unknown> {
  const next: Record<string, unknown> = isPlainObject(current) ? { ...current } : {}
  if (value === null || value.kind === 'null' || isEmptyValue(value)) delete next[propertyId]
  else next[propertyId] = encodePropertyValue(value)
  return next
}
