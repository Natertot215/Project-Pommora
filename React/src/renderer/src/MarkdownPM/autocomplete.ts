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
    if (rel >= open + 2 && rel <= close - 2) return { query: m[1], from: lineStart + open, to: lineStart + close }
  }
  return null
}

export function connectionInsert(title: string, from: number): { insert: string; caret: number } {
  const insert = `[[${title}]]`
  return { insert, caret: from + insert.length }
}
