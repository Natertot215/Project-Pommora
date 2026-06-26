import { tokenize } from '../tokens'
import { parseListMarker, isHeadingLine } from '../detect'
import { lineStartAt, lineEndAt } from '../input'
import type { FormatState } from '@shared/editorMenu'

export type { FormatState }

const HEADING_LEVEL = /^\s{0,3}(#{1,6})[ \t]+/

export function readFormatState(doc: string, from: number, to: number, focused: boolean): FormatState {
  // Inline marks are line-local, so tokenize only the caret's line (not the whole doc) and test
  // membership in line-relative coords. A cross-line selection can't sit inside one inline token anyway.
  const ls = lineStartAt(doc, from)
  const le = lineEndAt(doc, from)
  const line = doc.slice(ls, le)
  const tokens = tokenize(line)
  const f = from - ls
  const t = to - ls
  const wraps = (kind: string): boolean =>
    tokens.some((tk) => tk.kind === kind && tk.contentRange[0] <= f && t <= tk.contentRange[1])

  const lm = parseListMarker(line)
  const hm = isHeadingLine(line) ? HEADING_LEVEL.exec(line) : null

  return {
    focused,
    hasSelection: from !== to,
    bold: wraps('bold'),
    italic: wraps('italic'),
    strikethrough: wraps('strikethrough'),
    inlineCode: wraps('inlineCode'),
    link: tokens.some((tk) => tk.kind === 'link' && tk.range[0] <= f && t <= tk.range[1]),
    connection: tokens.some((tk) => tk.kind === 'wikiLink' && tk.range[0] <= f && t <= tk.range[1]),
    heading: hm ? hm[1].length : 0,
    list: lm?.kind === 'checkbox' ? 'task' : lm?.kind === 'ordered' ? 'ordered' : lm?.kind === 'bullet' ? 'bullet' : null,
    block: /^[ \t]*>[ \t]/.test(line) ? 'quote' : null
  }
}
