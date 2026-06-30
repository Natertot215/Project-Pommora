// Per-type column sizing {min, default, max} (Part 2 I-1). One DRY source; the width key is the
// column's declared type (reusing the pipeline's declaredType so title/tier/property all resolve
// through one path), with `_created_at` special-cased and a sane fallback. Values are starting
// points — tunable. Pure: no fs, no React.

import { type PropertyDefinition, RESERVED_PROPERTY_ID } from '@shared/properties'
import { declaredType } from '../pipeline/value'

export interface ColumnWidth {
  min: number
  default: number
  max: number
}

// Keyed by declaredType's outputs ('title' | 'tier' | a PropertyType) + 'created' (special-cased).
const WIDTHS: Record<string, ColumnWidth> = {
  title: { min: 120, default: 280, max: Number.POSITIVE_INFINITY }, // the primary column — uncapped, grows freely
  tier: { min: 80, default: 150, max: 300 },
  status: { min: 65, default: 120, max: 200 },
  select: { min: 65, default: 120, max: 220 },
  multi_select: { min: 100, default: 180, max: 320 },
  checkbox: { min: 40, default: 60, max: 90 },
  url: { min: 100, default: 180, max: 340 },
  file: { min: 100, default: 160, max: 300 },
  number: { min: 70, default: 110, max: 180 },
  datetime: { min: 90, default: 140, max: 210 },
  last_edited_time: { min: 90, default: 130, max: 190 },
  created: { min: 90, default: 130, max: 190 }
}

const FALLBACK: ColumnWidth = { min: 80, default: 150, max: 340 }

/** The {min, default, max} width for a column, keyed by its declared type (`_created_at` special-cased,
 *  unknown → a sane fallback). */
export function widthFor(columnId: string, schema: PropertyDefinition[]): ColumnWidth {
  if (columnId === RESERVED_PROPERTY_ID.createdAt) return WIDTHS.created
  const t = declaredType(columnId, schema)
  return (t !== undefined && WIDTHS[t]) || FALLBACK
}

/** Clamp a (resized) width to a column's [min, max]. */
export function clampWidth(width: number, columnId: string, schema: PropertyDefinition[]): number {
  const { min, max } = widthFor(columnId, schema)
  return Math.max(min, Math.min(max, width))
}
