// Cross-process contract for the table grip's right-click menu. The renderer sends where the click
// landed; main pops the native menu and resolves the chosen action (null if dismissed); the renderer
// applies it. No fs, no React — both sides import this.

export type TableMenuKind = 'column' | 'row' | 'header'

// `index` is the column index (kind 'column') or the visual row index (kind 'row'; 0 = header → kind
// 'header'). `align` carries the column's current alignment so the Align radio renders checked.
export interface TableMenuContext {
  kind: TableMenuKind
  index: number
  align?: 'left' | 'center' | 'right' | null
}

export type TableMenuAction =
  | 'align:left'
  | 'align:center'
  | 'align:right'
  | 'col:insert-left'
  | 'col:insert-right'
  | 'col:clear'
  | 'col:delete'
  | 'row:insert-above'
  | 'row:insert-below'
  | 'row:clear'
  | 'row:delete'
  | 'table:delete'
