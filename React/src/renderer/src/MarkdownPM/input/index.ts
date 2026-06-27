import { isInsideCode, isInsideWikilink } from '../parser'
import { parseListMarker, MAX_NESTING_LEVEL, blockquotePrefixRe, lineInCallout, calloutHeadPrefixLen, isBlockquoteLine } from '../detect'

export interface Edit {
  from: number
  to: number
  insert: string
  selection: number
}

export const lineStartAt = (doc: string, pos: number): number => doc.lastIndexOf('\n', pos - 1) + 1
export const lineEndAt = (doc: string, pos: number): number => {
  const i = doc.indexOf('\n', pos)
  return i === -1 ? doc.length : i
}

const lineMarkerRe = /^(\s*)(?:\d+\.|[-*+•→]|>|#{1,6})(?:[ \t]*\[[ xX]?\])?[ \t]+/
const shorthandCheckboxRe = /^([ \t]*)([-*+])\[([ xX]?)\]$/

// The leading `>`/callout prefix on a line (empty for top-level lines). A list continues / indents inside a
// callout because every list op reads the marker from after this prefix and re-emits the prefix on the new line.
// Only a REAL blockquote (whitespace after the `>`, per isBlockquoteLine) carries a prefix — so `>x` isn't
// mistaken for a quoted line by input ops while the renderer shows it as plain text (cross-layer agreement).
const blockPrefix = (line: string): string => (isBlockquoteLine(line) ? (blockquotePrefixRe.exec(line)?.[0] ?? '') : '')

export function continueListOnEnter(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null
  const ls = lineStartAt(doc, selStart)
  const lineEnd = lineEndAt(doc, selStart)
  const line = doc.slice(ls, lineEnd)
  const pfx = blockPrefix(line)
  const lm = parseListMarker(line.slice(pfx.length))
  if (lm === null) return null
  if (selStart < ls + pfx.length + lm.contentStart) return null // caret in/before the marker zone

  const indent = line.slice(pfx.length, pfx.length + lm.markerStart)

  // Renumber following same-level siblings so the run stays sequential (insert between 1 and 2 → 1, 2, 3).
  if (lm.kind === 'ordered') {
    const restOfLine = doc.slice(selStart, lineEnd)
    let counter = parseInt(lm.digits ?? '0', 10) + 1
    const newPrefix = `\n${pfx}${indent}${counter}. `
    const caret = selStart + newPrefix.length
    let insert = `${newPrefix}${restOfLine}`
    let to = lineEnd
    counter++
    for (let p = lineEnd; p < doc.length; ) {
      const fs = p + 1
      const fe = lineEndAt(doc, fs)
      const fline = doc.slice(fs, fe)
      const fpfx = blockPrefix(fline)
      const flm = parseListMarker(fline.slice(fpfx.length))
      if (flm === null || flm.kind !== 'ordered' || fpfx !== pfx || fline.slice(fpfx.length, fpfx.length + flm.markerStart) !== indent) break
      insert += `\n${pfx}${indent}${counter}. ${fline.slice(fpfx.length + flm.contentStart)}`
      counter++
      to = fe
      p = fe
    }
    return { from: selStart, to, insert, selection: caret }
  }

  const next = lm.kind === 'checkbox' ? `${lm.bullet ?? '-'} [ ] ` : `${lm.bullet ?? '-'} `
  const insert = `\n${pfx}${indent}${next}`
  return { from: selStart, to: selStart, insert, selection: selStart + insert.length }
}

export function continueBlockquoteOnEnter(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null
  const ls = lineStartAt(doc, selStart)
  // Ungated on purpose: continues a `>x` (no-space) line too, which blockPrefix's isBlockquoteLine gate would drop.
  const m = blockquotePrefixRe.exec(doc.slice(ls, lineEndAt(doc, selStart)))
  if (m === null || selStart < ls + m[0].length) return null
  const insert = `\n${m[0].replace(/[ \t]+$/, '')} ` // normalize to a single trailing space
  return { from: selStart, to: selStart, insert, selection: selStart + insert.length }
}

// `||` at line start → the callout head `> [!callout] `. Fires on the second `|` (already-typed first `|`
// sits at c-1). Line-start only, so a `|` inside a table row can't trigger it. When the callout would be the
// last block in the doc, a trailing empty line is added so the caret has somewhere to land to exit the box.
export function calloutShorthand(doc: string, selStart: number, selEnd: number, inserted: string): Edit | null {
  if (inserted !== '|' || selStart !== selEnd) return null
  const c = selStart
  const ls = lineStartAt(doc, c)
  if (ls !== c - 1 || doc[c - 1] !== '|') return null // only a bare `|` at line start
  const lineEnd = lineEndAt(doc, c)
  const head = '> [!callout] '
  // Consume just the `||` (replace the first `|`; the second is suppressed) so any content already on the line
  // is preserved as the callout's first-line body. Separate the new callout from an adjacent blockquote/callout
  // with a blank line so they read as two boxes, not one touching pair. Add a trailing exit line when the
  // callout is alone on its line and there's nothing below to land on (or a quote it must separate from).
  const onlyOnLine = c === lineEnd
  const prevIsQuote = ls > 0 && isBlockquoteLine(doc.slice(lineStartAt(doc, ls - 1), ls - 1))
  const nextStart = lineEnd + 1
  const nextIsQuote = nextStart <= doc.length && isBlockquoteLine(doc.slice(nextStart, lineEndAt(doc, nextStart)))
  const lead = prevIsQuote ? '\n' : ''
  const trailing = onlyOnLine && (lineEnd === doc.length || nextIsQuote) ? '\n' : ''
  const insert = lead + head + trailing
  return { from: ls, to: c, insert, selection: ls + lead.length + head.length }
}

// Shift+Enter normally exits a construct (plain newline). Inside a callout it instead stays in the box —
// continuing the `> ` prefix — so multi-line content and lists can be built without escaping; exit is by
// caret placement on the empty line below.
export function shiftEnterEdit(doc: string, selStart: number, selEnd: number): Edit {
  // Inside a callout the new line keeps the box prefix (works with a selection too — a plain `\n` there would
  // drop an un-prefixed line into the middle of the run and split the callout). Require BOTH ends in the
  // callout: a selection straddling the box edge falls back to a plain `\n` so outside text isn't pulled in.
  if (lineInCallout(doc, selStart) && lineInCallout(doc, selEnd)) {
    const ls = lineStartAt(doc, selStart)
    const pfx = (blockquotePrefixRe.exec(doc.slice(ls, lineEndAt(doc, selStart)))?.[0] ?? '> ').replace(/[ \t]+$/, '')
    const insert = `\n${pfx} `
    return { from: selStart, to: selEnd, insert, selection: selStart + insert.length }
  }
  return { from: selStart, to: selEnd, insert: '\n', selection: selStart + 1 }
}

export function indentListOnTab(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null
  const ls = lineStartAt(doc, selStart)
  const line = doc.slice(ls, lineEndAt(doc, selStart))
  const pfx = blockPrefix(line)
  const lm = parseListMarker(line.slice(pfx.length))
  if (lm === null || lm.level >= MAX_NESTING_LEVEL) return null
  // Indent after the `>` prefix so a list inside a callout nests without breaking the blockquote.
  return { from: ls + pfx.length, to: ls + pfx.length, insert: '\t', selection: selStart + 1 }
}

// Backspace at a marker's content-start deletes the whole marker in one step (no nibbling `- [ ] ` into broken
// syntax). Prefix-aware: inside a quote/callout it deletes the INNER marker (stay in the box), joins to the
// previous box line when there's no inner marker, and removes the whole `> [!type] ` head cleanly.
export function smartBackspace(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null
  const ls = lineStartAt(doc, selStart)
  const line = doc.slice(ls, lineEndAt(doc, selStart))

  // Inside a callout, never strip a lone `>` (that drops the line out of the box / splits the callout into a
  // stray quote). Delete an inner list marker, strip the whole `> [!type] ` head, or join to the line above.
  if (lineInCallout(doc, selStart)) {
    const pfx = blockPrefix(line)
    const headLen = calloutHeadPrefixLen(line)
    if (headLen !== null) {
      // Backspace anywhere inside the hidden `> [!type] ` head removes the whole callout in one step, so a
      // caret that wandered into the tag can't corrupt it char-by-char and silently demote the box to a quote.
      if (selStart > ls && selStart <= ls + headLen) return { from: ls, to: ls + headLen, insert: '', selection: ls }
      return null
    }
    const lm = parseListMarker(line.slice(pfx.length))
    if (lm) {
      const innerContentStart = ls + pfx.length + lm.contentStart
      if (selStart !== innerContentStart) return null
      return { from: ls + pfx.length, to: innerContentStart, insert: '', selection: ls + pfx.length }
    }
    if (selStart === ls + pfx.length && ls > 0) return { from: ls - 1, to: ls + pfx.length, insert: '', selection: ls - 1 }
    return null
  }

  // Top-level (incl. plain quotes): delete the whole marker prefix in one step.
  const m = lineMarkerRe.exec(line)
  if (m === null) return null
  const contentStart = ls + m[0].length
  if (selStart !== contentStart) return null
  return { from: ls, to: contentStart, insert: '', selection: ls }
}

export function canonicalizeCheckbox(doc: string, selStart: number, selEnd: number, inserted: string): Edit | null {
  if (inserted !== ' ' || selStart !== selEnd) return null
  const ls = lineStartAt(doc, selStart)
  const before = doc.slice(ls, selStart)
  const pfx = blockPrefix(before)
  const m = shorthandCheckboxRe.exec(before.slice(pfx.length))
  if (m === null) return null
  const [, ws, marker, inner] = m
  const gfm = `${ws}${marker} [${inner.toLowerCase() === 'x' ? 'x' : ' '}] `
  return { from: ls + pfx.length, to: selStart, insert: gfm, selection: ls + pfx.length + gfm.length }
}

interface PairSpec {
  close: string
  multi?: string
}
const PAIRS: Record<string, PairSpec> = {
  '*': { close: '*', multi: '**' },
  _: { close: '_', multi: '__' },
  '`': { close: '`', multi: '``' },
  '(': { close: ')', multi: '))' },
  '[': { close: ']', multi: ']]' },
  '{': { close: '}' }
}

// Single `[` only pairs at line start / after whitespace (so `-[` flows).
export function autoPair(doc: string, selStart: number, selEnd: number, inserted: string): Edit | null {
  if (selStart !== selEnd) return null
  const c = selStart
  if (isInsideCode(c, doc)) return null
  const prev = doc[c - 1]
  const pair = PAIRS[inserted]
  if (!pair) return null

  if (pair.multi && prev === inserted) {
    // Consume an already-paired closer so `[|]` + `[` → `[[|]]`, not a stray `[[|]]]`.
    const insert = doc[c] === pair.close ? inserted + pair.close : inserted + pair.multi
    return { from: c, to: c, insert, selection: c + 1 }
  }
  if (inserted === '[') {
    const atLineStart = c === lineStartAt(doc, c)
    if (atLineStart || prev === ' ' || prev === '\t' || prev === '\n') {
      return { from: c, to: c, insert: inserted + pair.close, selection: c + 1 }
    }
    return null
  }
  if (inserted === '(' || inserted === '{') {
    return { from: c, to: c, insert: inserted + pair.close, selection: c + 1 }
  }
  return null
}

export function autoDelete(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd || selStart === 0) return null
  const close = PAIRS[doc[selStart - 1]]?.close
  if (close === undefined || doc[selStart] !== close) return null
  return { from: selStart - 1, to: selStart + 1, insert: '', selection: selStart - 1 }
}

export function bracketSkipOnEnter(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd || isInsideCode(selStart, doc)) return null
  const c = selStart
  const closer = doc[c]
  const opener = doc[c - 1]
  const matched =
    (opener === '[' && closer === ']') || (opener === '(' && closer === ')') || (opener === '{' && closer === '}')
  if (!matched) return null
  // [[ | ]] → jump past both closers
  if (opener === '[' && doc[c + 1] === ']' && doc[c - 2] === '[') {
    return { from: c, to: c, insert: '', selection: c + 2 }
  }
  return { from: c, to: c, insert: '', selection: c + 1 }
}

// Fires on the NEXT char so collisions resolve first.
export function dashArrow(doc: string, selStart: number, selEnd: number, inserted: string): Edit | null {
  if (selStart !== selEnd || inserted.length !== 1) return null
  const c = selStart
  if (isInsideCode(c, doc)) return null

  // em-dash: "--" then a non-dash char (the 3-back check preserves --- HR)
  if (inserted !== '-' && c >= 2 && doc[c - 1] === '-' && doc[c - 2] === '-' && doc[c - 3] !== '-') {
    return { from: c - 2, to: c, insert: `—${inserted}`, selection: c }
  }
  if (inserted === '-' && doc[c - 1] === '–') return { from: c - 1, to: c, insert: '—', selection: c }
  if (inserted === '>') {
    if (doc[c - 1] === '←') return { from: c - 1, to: c, insert: '↔', selection: c }
    if (doc[c - 1] === '-') return { from: c - 1, to: c, insert: '→', selection: c }
  }
  if (inserted === '-' && doc[c - 1] === '<') return { from: c - 1, to: c, insert: '←', selection: c }
  if (inserted === ' ' && c >= 2 && doc[c - 1] === '-' && doc[c - 2] === ' ') {
    const ls = lineStartAt(doc, c)
    // Measure "is there prose before the dash" AFTER the blockquote prefix — otherwise the `> ` on a callout /
    // quote line counts as content and a `- ` bullet there gets eaten into an en-dash.
    const pfx = blockPrefix(doc.slice(ls, lineEndAt(doc, c)))
    const before = doc.slice(ls + pfx.length, c - 2)
    if (/\S/.test(before) && !isInsideWikilink(c, doc)) {
      return { from: c - 1, to: c, insert: '– ', selection: c + 1 }
    }
  }
  return null
}
