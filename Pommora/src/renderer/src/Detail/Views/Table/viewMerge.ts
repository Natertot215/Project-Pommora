import type { ColumnStyle } from '@shared/columnStyles'
import type { ColumnAlign, SavedView } from '@shared/views'

/**
 * Fold the live local overrides + a field patch into one persistable SavedView. Order is already baked
 * into `liveView`; width + alignment + style + collapse are applied here. Every persist routes through
 * this so one mutation's patch can't drop another's unsaved override (resize-then-hide, align-then-
 * collapse, …) — the exact Swift reorder/resize data-loss that H-2 guards against. A patch field wins
 * over the fold.
 */
export function mergeOverrides(
  liveView: SavedView,
  widths: Record<string, number>,
  aligns: Record<string, ColumnAlign>,
  collapsed: Set<string>,
  patch: Partial<SavedView>,
  styles: Record<string, ColumnStyle> = {},
): SavedView {
  return {
    ...liveView,
    collapsed_groups: [...collapsed],
    column_widths: { ...liveView.column_widths, ...widths },
    column_alignments: { ...liveView.column_alignments, ...aligns },
    column_styles: mergeStyleRecords(liveView.column_styles, styles),
    ...patch,
  }
}

/** Fold style overrides per-KEY into the saved record — style entries are objects, so an
 *  entry-level spread would wipe a column's saved sibling keys (a time_format override must
 *  not drop the saved look). */
export function mergeStyleRecords(
  saved: Record<string, ColumnStyle> | undefined,
  overrides: Record<string, ColumnStyle>,
): Record<string, ColumnStyle> {
  const folded = Object.fromEntries(
    Object.entries(overrides).map(([id, s]) => [id, { ...saved?.[id], ...s }]),
  )
  return { ...saved, ...folded }
}
