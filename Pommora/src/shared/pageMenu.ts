// The page context-menu meta block (Open · Rename · Change Icon · Delete) — shared by the table
// cell's title menu (cellMenu) and the card's right-click menu (cardMenu) so the page-meta actions
// stay single-sourced. An already-open page reads "Open" (focus its tab) rather than "Open in New Tab".

export type PageMetaAction = 'title:newtab' | 'title:rename' | 'title:icon' | 'title:delete'

export function pageMetaMenuItems(
  alreadyOpen?: boolean,
): Array<{ label: string; action: PageMetaAction; separatorBefore?: boolean }> {
  return [
    { label: alreadyOpen ? 'Open' : 'Open in New Tab', action: 'title:newtab' },
    { label: 'Rename', action: 'title:rename', separatorBefore: true },
    { label: 'Change Icon', action: 'title:icon' },
    { label: 'Delete', action: 'title:delete', separatorBefore: true },
  ]
}
