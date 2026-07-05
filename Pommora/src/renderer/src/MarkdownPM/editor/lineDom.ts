import type { EditorView } from '@codemirror/view'

// The .cm-line DOM element containing `pos` (or null if not rendered) — walk up from the position's node to its
// line wrapper. Used to read a line's OUTER box edge, which for a callout/quote/code box lies outside the visible
// border (where the drop lands), unlike coordsAtPos (the inner text position, which sits inside the box).
export function lineElementAt(view: EditorView, pos: number): HTMLElement | null {
  let node: Node | null = view.domAtPos(pos).node
  while (node && !(node instanceof HTMLElement && node.classList.contains('cm-line'))) node = node.parentNode
  return node instanceof HTMLElement ? node : null
}
