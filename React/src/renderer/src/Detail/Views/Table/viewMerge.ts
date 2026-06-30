import type { SavedView } from '@shared/views'

/**
 * Fold the live local overrides + a field patch into one persistable SavedView. Order is already baked
 * into `liveView`; width + collapse are applied here. Every persist routes through this so one
 * mutation's patch can't drop another's unsaved override (resize-then-hide, collapse-then-reorder, …) —
 * the exact Swift reorder/resize data-loss that H-2 guards against. A patch field wins over the fold.
 */
export function mergeOverrides(
  liveView: SavedView,
  widths: Record<string, number>,
  collapsed: Set<string>,
  patch: Partial<SavedView>
): SavedView {
  return {
    ...liveView,
    collapsed_groups: [...collapsed],
    column_widths: { ...liveView.column_widths, ...widths },
    ...patch
  }
}
