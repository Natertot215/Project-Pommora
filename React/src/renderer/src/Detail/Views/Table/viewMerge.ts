import type { ColumnAlign, SavedView } from '@shared/views'

/**
 * Fold the live local overrides + a field patch into one persistable SavedView. Order is already baked
 * into `liveView`; width + alignment + collapse are applied here. Every persist routes through this so one
 * mutation's patch can't drop another's unsaved override (resize-then-hide, align-then-collapse, …) —
 * the exact Swift reorder/resize data-loss that H-2 guards against. A patch field wins over the fold.
 */
export function mergeOverrides(
  liveView: SavedView,
  widths: Record<string, number>,
  aligns: Record<string, ColumnAlign>,
  collapsed: Set<string>,
  patch: Partial<SavedView>
): SavedView {
  return {
    ...liveView,
    collapsed_groups: [...collapsed],
    column_widths: { ...liveView.column_widths, ...widths },
    column_alignments: { ...liveView.column_alignments, ...aligns },
    ...patch
  }
}
