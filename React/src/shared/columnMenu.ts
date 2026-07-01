import type { ColumnAlign } from './views'

/** The table-view column-header right-click menu (E-1/E-5): hide the column, or set its text alignment.
 *  The renderer applies the resolved action, or no-ops on null (dismissed). Mirrors calloutMenu's shape. */
export type ColumnMenuAction = 'column:hide' | `align:${ColumnAlign}`

/** Menu context — the current alignment (for the checked radio) + which items apply. The Title column is
 *  the primary column: neither alignable nor hideable, so it pops an empty (⇒ dismissed) menu. */
export interface ColumnMenuContext {
  align: ColumnAlign
  alignable: boolean
  hideable: boolean
}
