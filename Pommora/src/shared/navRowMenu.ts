// The NavWindow row/card right-click menu (D-3) — a NATIVE Electron menu (like the tab/cell menus),
// not an in-renderer surface. The renderer sends the row's live membership state; main pops the menu
// and returns the chosen action (or null on dismiss); the renderer runs it against the row it held.

export interface NavRowMenuContext {
  /** Open lands a tab — the label reads "Open" when the target is already open, else "Open in New Tab". */
  canOpenNewTab: boolean
  alreadyOpen: boolean
  /** Only pages offer Open in Preview. */
  isPage: boolean
  isPinned: boolean
  isFavorite: boolean
}

export type NavRowMenuAction =
  | 'open-new-tab'
  | 'open-preview'
  | 'pin'
  | 'unpin'
  | 'favorite'
  | 'unfavorite'
  | 'remove'
