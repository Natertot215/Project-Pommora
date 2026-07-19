// The card's right-click menu (I-6): page-meta actions (Open · Rename · Change Icon · Delete) plus an
// Add Property ▸ submenu of the card's blank, addable properties. The renderer builds the addable
// list (already grouped) and routes the chosen action; main maps this model to Electron MenuItems.

export type CardMenuAction =
  | 'title:newtab'
  | 'title:rename'
  | 'title:icon'
  | 'title:delete'
  | `add:${string}`

export interface CardMenuContext {
  /** Blank, addable properties — already ordered by the renderer (pane-kinds first). */
  addable: Array<{ id: string; name: string }>
  /** An open page reads "Open" (focus its tab) rather than "Open in New Tab". */
  alreadyOpen?: boolean
}

export interface CardMenuModel {
  items: Array<{ label: string; action: CardMenuAction; separatorBefore?: boolean }>
  /** The Add Property ▸ submenu; absent when the card has no addable property. */
  addProperty?: Array<{ label: string; action: CardMenuAction }>
}

/** The pure per-card item model — main maps it to Electron MenuItems. */
export function cardMenuModel(ctx: CardMenuContext): CardMenuModel {
  return {
    items: [
      { label: ctx.alreadyOpen ? 'Open' : 'Open in New Tab', action: 'title:newtab' },
      { label: 'Rename', action: 'title:rename', separatorBefore: true },
      { label: 'Change Icon', action: 'title:icon' },
      { label: 'Delete', action: 'title:delete', separatorBefore: true },
    ],
    addProperty:
      ctx.addable.length > 0
        ? ctx.addable.map((d) => ({ label: d.name, action: `add:${d.id}` as const }))
        : undefined,
  }
}
