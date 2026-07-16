// The tab right-click menu (I-12) — a NATIVE Electron menu (like the sidebar/cell menus), not an
// in-renderer surface. The renderer sends the tab's context; main pops the menu and returns the chosen
// action (or null on dismiss); the renderer runs it against the tab id it held.

export interface TabMenuContext {
  /** A pinned tab offers Unpin only (no Close — D-10; unpin reveals the ×). */
  pinned: boolean
  /** The NavView tab can't be pinned. */
  isNewTab: boolean
  /** Whether any unpinned tab sits to the right (gates Close to the Right). */
  hasRight: boolean
}

export type TabMenuAction = 'pin' | 'unpin' | 'close' | 'close-right'
