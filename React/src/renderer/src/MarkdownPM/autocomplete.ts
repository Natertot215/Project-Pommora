// Pure detection for the [[ autocomplete: is the caret inside a non-empty `[[query]]` (not an
// image embed), and if so what's the query + the full token range to replace on accept. Mirrors the
// Swift trigger (placeholder non-empty; `![[ ]]` suppressed).
const WIKI_RE = /(?<!!)\[\[([^[\]\r\n]*)\]\]/g

export interface AutocompleteQuery {
  /** The partial title typed between the brackets. */
  query: string
  /** The full `[[…]]` span to replace when a candidate is accepted. */
  from: number
  to: number
}

export function autocompleteQuery(doc: string, caret: number): AutocompleteQuery | null {
  const lineStart = doc.lastIndexOf('\n', caret - 1) + 1
  const nl = doc.indexOf('\n', caret)
  const lineEnd = nl === -1 ? doc.length : nl
  const line = doc.slice(lineStart, lineEnd)
  const rel = caret - lineStart
  WIKI_RE.lastIndex = 0
  for (let m = WIKI_RE.exec(line); m; m = WIKI_RE.exec(line)) {
    const open = m.index
    const close = m.index + m[0].length
    if (rel >= open + 2 && rel <= close - 2) {
      if (m[1].trim() === '') return null // empty placeholder → no panel (Swift parity)
      return { query: m[1], from: lineStart + open, to: lineStart + close }
    }
  }
  return null
}

/** The replacement for accepting `title`: the whole token becomes `[[title]]`, caret after `]]`. */
export function connectionInsert(title: string, from: number): { insert: string; caret: number } {
  const insert = `[[${title}]]`
  return { insert, caret: from + insert.length }
}
