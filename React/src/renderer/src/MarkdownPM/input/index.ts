import { isInsideCode, isInsideWikilink } from '../parser'
import { parseListMarker, MAX_NESTING_LEVEL, blockquotePrefixRe } from '../detect'

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

export function continueListOnEnter(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null
  const ls = lineStartAt(doc, selStart)
  const lineEnd = lineEndAt(doc, selStart)
  const line = doc.slice(ls, lineEnd)
  const lm = parseListMarker(line)
  if (lm === null) return null
  if (selStart < ls + lm.contentStart) return null // caret in/before the marker zone

  const indent = line.slice(0, lm.markerStart)

  // Renumber following same-level siblings so the run stays sequential (insert between 1 and 2 → 1, 2, 3).
  if (lm.kind === 'ordered') {
    const restOfLine = doc.slice(selStart, lineEnd)
    let counter = parseInt(lm.digits ?? '0', 10) + 1
    const newPrefix = `\n${indent}${counter}. `
    const caret = selStart + newPrefix.length
    let insert = `${newPrefix}${restOfLine}`
    let to = lineEnd
    counter++
    for (let p = lineEnd; p < doc.length; ) {
      const fs = p + 1
      const fe = lineEndAt(doc, fs)
      const fline = doc.slice(fs, fe)
      const flm = parseListMarker(fline)
      if (flm === null || flm.kind !== 'ordered' || fline.slice(0, flm.markerStart) !== indent) break
      insert += `\n${indent}${counter}. ${fline.slice(flm.contentStart)}`
      counter++
      to = fe
      p = fe
    }
    return { from: selStart, to, insert, selection: caret }
  }

  const next = lm.kind === 'checkbox' ? `${lm.bullet ?? '-'} [ ] ` : `${lm.bullet ?? '-'} `
  const insert = `\n${indent}${next}`
  return { from: selStart, to: selStart, insert, selection: selStart + insert.length }
}

export function continueBlockquoteOnEnter(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null
  const ls = lineStartAt(doc, selStart)
  const m = blockquotePrefixRe.exec(doc.slice(ls, lineEndAt(doc, selStart)))
  if (m === null || selStart < ls + m[0].length) return null
  const insert = `\n${m[0].replace(/[ \t]+$/, '')} ` // normalize to a single trailing space
  return { from: selStart, to: selStart, insert, selection: selStart + insert.length }
}

export function indentListOnTab(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null
  const ls = lineStartAt(doc, selStart)
  const lm = parseListMarker(doc.slice(ls, lineEndAt(doc, selStart)))
  if (lm === null || lm.level >= MAX_NESTING_LEVEL) return null
  return { from: ls, to: ls, insert: '\t', selection: selStart + 1 }
}

// Delete the whole marker prefix in one step instead of nibbling `- [ ] ` into broken syntax.
export function smartBackspace(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null
  const ls = lineStartAt(doc, selStart)
  const line = doc.slice(ls, lineEndAt(doc, selStart))
  const m = lineMarkerRe.exec(line)
  if (m === null) return null
  const contentStart = ls + m[0].length
  if (selStart !== contentStart) return null
  return { from: ls, to: contentStart, insert: '', selection: ls }
}

export function canonicalizeCheckbox(doc: string, selStart: number, selEnd: number, inserted: string): Edit | null {
  if (inserted !== ' ' || selStart !== selEnd) return null
  const ls = lineStartAt(doc, selStart)
  const m = shorthandCheckboxRe.exec(doc.slice(ls, selStart))
  if (m === null) return null
  const [, ws, marker, inner] = m
  const gfm = `${ws}${marker} [${inner.toLowerCase() === 'x' ? 'x' : ' '}] `
  return { from: ls, to: selStart, insert: gfm, selection: ls + gfm.length }
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
    const before = doc.slice(ls, c - 2)
    if (/\S/.test(before) && !isInsideWikilink(c, doc)) {
      return { from: c - 1, to: c, insert: '– ', selection: c + 1 }
    }
  }
  return null
}
