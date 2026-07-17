import { pageLinkPattern } from '@shared/connections'
import { lineStartAt, lineEndAt } from './input'

export interface AutocompleteQuery {
  query: string
  /** The full `[[…]]` span to replace when a candidate is accepted. */
  from: number
  to: number
}

export function autocompleteQuery(doc: string, caret: number): AutocompleteQuery | null {
  const lineStart = lineStartAt(doc, caret)
  const line = doc.slice(lineStart, lineEndAt(doc, caret))
  const rel = caret - lineStart
  const re = pageLinkPattern()
  for (let m = re.exec(line); m; m = re.exec(line)) {
    const open = m.index
    const close = m.index + m[0].length
    if (rel >= open + 2 && rel <= close - 2)
      return { query: m[1], from: lineStart + open, to: lineStart + close }
  }
  return null
}

export function connectionInsert(title: string, from: number): { insert: string; caret: number } {
  const insert = `[[${title}]]`
  return { insert, caret: from + insert.length }
}

// Panel geometry — shared by the main editor and table cells. AC_ROW_H/AC_PADDING track .mdpm-ac in Styles.css.
export const AC_MAX = 6
const AC_ROW_H = 28
const AC_PADDING = 8
const AC_MAX_ROWS = 4
const AC_GAP = 4

// Anchor the panel below the caret; flip above when it would overflow the viewport bottom. Coords are
// viewport-relative (the panel is position:fixed), so this works the same from the main editor or a cell.
export function acPanelTop(caretTop: number, caretBottom: number, count: number): number {
  const h = Math.min(count, AC_MAX_ROWS) * AC_ROW_H + AC_PADDING
  return caretBottom + AC_GAP + h > window.innerHeight
    ? caretTop - h - AC_GAP
    : caretBottom + AC_GAP
}
