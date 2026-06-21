import { tokenize } from '../tokens'
import { parseListMarker, isHeadingLine } from '../detect'
import { lineStartAt, lineEndAt } from '../input'
import type { FormatState } from '@shared/editorMenu'

export type { FormatState }

const HEADING_LEVEL = /^\s{0,3}(#{1,6})[ \t]+/

export function readFormatState(doc: string, from: number, to: number, focused: boolean): FormatState {
  const tokens = tokenize(doc)
  const wraps = (kind: string): boolean =>
    tokens.some((tk) => tk.kind === kind && tk.contentRange[0] <= from && to <= tk.contentRange[1])

  const line = doc.slice(lineStartAt(doc, from), lineEndAt(doc, from))
  const lm = parseListMarker(line)
  const hm = isHeadingLine(line) ? HEADING_LEVEL.exec(line) : null

  return {
    focused,
    hasSelection: from !== to,
    bold: wraps('bold'),
    italic: wraps('italic'),
    strikethrough: wraps('strikethrough'),
    inlineCode: wraps('inlineCode'),
    link: tokens.some((tk) => tk.kind === 'link' && tk.range[0] <= from && to <= tk.range[1]),
    connection: tokens.some((tk) => tk.kind === 'wikiLink' && tk.range[0] <= from && to <= tk.range[1]),
    heading: hm ? hm[1].length : 0,
    list: lm?.kind === 'checkbox' ? 'task' : lm?.kind === 'ordered' ? 'ordered' : lm?.kind === 'bullet' ? 'bullet' : null,
    block: /^[ \t]*>[ \t]/.test(line) ? 'quote' : null
  }
}
