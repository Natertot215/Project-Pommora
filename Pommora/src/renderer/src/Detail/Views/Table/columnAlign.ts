// Per-column text alignment (E-5..E-7). Mirrors columnWidths: a pure render-layer helper keyed by the
// column's declared type. The E-6 default is center for the chip/box types (contexts + checkbox/status/
// select/multi-select), left for everything else; a SavedView `column_alignments` entry overrides it.
// Pure: no fs, no React.

import type { PropertyDefinition } from '@shared/properties'
import { RESERVED_PROPERTY_ID } from '@shared/properties'
import type { ColumnAlign, SavedView } from '@shared/views'
import { declaredType } from '../pipeline/value'

// declaredType outputs that center by default (E-6): the chip/box-shaped values — contexts ('tier' for
// the reserved tier columns, 'context' for a user context prop), checkbox/status/select/multi_select, and
// the user datetime property, whose formatted value reads centered. The reserved Modified timestamp keeps
// its left metadata treatment (like Title).
const CENTERED = new Set(['checkbox', 'status', 'select', 'multi_select', 'tier', 'context', 'datetime'])

/** The E-6 default alignment for a column, from its declared type. Title is always left (its primary
 *  icon+text treatment); unknown types fall back to left. */
export function defaultAlignFor(columnId: string, schema: PropertyDefinition[]): ColumnAlign {
  if (columnId === RESERVED_PROPERTY_ID.title) return 'left'
  const t = declaredType(columnId, schema)
  return t !== undefined && CENTERED.has(t) ? 'center' : 'left'
}

/** The resolved alignment for a column: a saved `column_alignments` override, else the E-6 type default. */
export function alignFor(columnId: string, schema: PropertyDefinition[], view: SavedView): ColumnAlign {
  return view.column_alignments?.[columnId] ?? defaultAlignFor(columnId, schema)
}
