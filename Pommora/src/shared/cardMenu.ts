// The card's right-click menu: page-meta actions (Open · Rename · Change Icon · Delete), an
// Add Property ▸ submenu of the card's blank, addable properties, and a Move To ▸ submenu that walks
// the Collection/Set tree (each node relocates the page there via movePage). The renderer builds both
// trees (already ordered) and routes the chosen action; main maps this model to Electron MenuItems.

import { type PageMetaAction, pageMetaMenuItems } from './pageMenu'

export type CardMenuAction = PageMetaAction | `add:${string}` | `move:${string}`

/** One node of the Move To ▸ tree — a container the page can move into. `children` are its sub-sets
 *  (a nested submenu). `path` is the destination container path (movePage's newParentPath). */
export interface MoveTarget {
  label: string
  path: string
  children?: MoveTarget[]
}

export interface CardMenuContext {
  /** Blank, addable properties — already ordered by the renderer (pane-kinds first). */
  addable: Array<{ id: string; name: string }>
  /** The Collection/Set tree the page can move into (renderer-built from the nexus tree). */
  moveTargets?: MoveTarget[]
  /** The page's current parent path — its own "Move Here" is disabled (moving there is a no-op). */
  currentParentPath?: string
  /** An open page reads "Open" (focus its tab) rather than "Open in New Tab". */
  alreadyOpen?: boolean
}

export interface CardMenuModel {
  items: Array<{ label: string; action: CardMenuAction; separatorBefore?: boolean }>
  /** The Add Property ▸ submenu; absent when the card has no addable property. */
  addProperty?: Array<{ label: string; action: CardMenuAction }>
  /** The Move To ▸ tree; absent when there's nowhere else to move the page. */
  moveTo?: MoveTarget[]
  currentParentPath?: string
}

/** The pure per-card item model — main maps it to Electron MenuItems. */
export function cardMenuModel(ctx: CardMenuContext): CardMenuModel {
  return {
    items: pageMetaMenuItems(ctx.alreadyOpen),
    addProperty:
      ctx.addable.length > 0
        ? ctx.addable.map((d) => ({ label: d.name, action: `add:${d.id}` as const }))
        : undefined,
    moveTo: ctx.moveTargets && ctx.moveTargets.length > 0 ? ctx.moveTargets : undefined,
    currentParentPath: ctx.currentParentPath,
  }
}
