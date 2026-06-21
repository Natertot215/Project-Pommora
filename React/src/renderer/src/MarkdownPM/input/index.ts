// Pure, framework-free typing transforms. Each takes the document + selection (+ the inserted char
// for keystroke-reactive ones) and returns an Edit to apply, or null to fall through. Input-time
// only (single-char insert / specific keys); paste preserves literal text by construction.
import { isInsideCode, isInsideWikilink } from '../parser'
import { parseListMarker, MAX_NESTING_LEVEL, blockquotePrefixRe } from '../detect'

/** A single atomic edit: replace [from, to) with `insert`, then place the caret at `selection`. */
export interface Edit {
  from: number
  to: number
  insert: string
  selection: number
}

const lineStartAt = (doc: string, pos: number): number => doc.lastIndexOf('\n', pos - 1) + 1
const lineEndAt = (doc: string, pos: number): number => {
  const i = doc.indexOf('\n', pos)
  return i === -1 ? doc.length : i
}

// Any line marker (for smart-backspace): bullet / ordered / blockquote / heading.
const lineMarkerRe = /^(\s*)(?:\d+\.|[-*+•]|>|#{1,6})(?:[ \t]*\[[ xX]?\])?[ \t]+/
// The `-[]` / `-[ ]` / `-[x]` shorthand (no space before the bracket), up to the caret.
const shorthandCheckboxRe = /^([ \t]*)([-*+])\[([ xX]?)\]$/

/** Enter inside a list item → open the next item (indent preserved, checkbox continued fresh
 *  unchecked). Empty items continue too (Shift+Enter is the only exit — handled by the caller). */
export function continueListOnEnter(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null
  const ls = lineStartAt(doc, selStart)
  const line = doc.slice(ls, lineEndAt(doc, selStart))
  const lm = parseListMarker(line)
  if (lm === null) return null
  if (selStart < ls + lm.contentStart) return null // caret in/before the marker zone

  const next =
    lm.kind === 'ordered'
      ? `${parseInt(lm.digits ?? '0', 10) + 1}. `
      : lm.kind === 'checkbox'
        ? `${lm.bullet ?? '-'} [ ] ` // continue checkboxes as a fresh unchecked box
        : `${lm.bullet ?? '-'} `
  const insert = `\n${line.slice(0, lm.markerStart)}${next}`
  return { from: selStart, to: selStart, insert, selection: selStart + insert.length }
}

/** Enter inside a blockquote → continue with the same `> ` prefix (nesting preserved). Shift+Enter
 *  exits (the caller's separate binding inserts a plain newline). Caret in/before the marker → null. */
export function continueBlockquoteOnEnter(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null
  const ls = lineStartAt(doc, selStart)
  const m = blockquotePrefixRe.exec(doc.slice(ls, lineEndAt(doc, selStart)))
  if (m === null || selStart < ls + m[0].length) return null
  const insert = `\n${m[0].replace(/[ \t]+$/, '')} ` // normalize to a single trailing space
  return { from: selStart, to: selStart, insert, selection: selStart + insert.length }
}

/** Tab on a list line → insert one tab at line start (nest a level), capped at the max nesting.
 *  Non-list lines / selections fall through (return null) so Tab keeps its default behavior. */
export function indentListOnTab(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null
  const ls = lineStartAt(doc, selStart)
  const lm = parseListMarker(doc.slice(ls, lineEndAt(doc, selStart)))
  if (lm === null || lm.level >= MAX_NESTING_LEVEL) return null
  return { from: ls, to: ls, insert: '\t', selection: selStart + 1 }
}

/** Backspace at the START of a marker line's content → delete the WHOLE marker prefix in one
 *  step, caret to line start (instead of nibbling `- [ ] ` into broken syntax). All markers. */
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

/** Typing the content-starting space after `-[]` / `-[ ]` / `-[x]` → canonical GFM `- [ ] ` /
 *  `- [x] `, caret after the trailing space so typing flows. (Replaces the typed space.) */
export function canonicalizeCheckbox(doc: string, selStart: number, selEnd: number, inserted: string): Edit | null {
  if (inserted !== ' ' || selStart !== selEnd) return null
  const ls = lineStartAt(doc, selStart)
  const m = shorthandCheckboxRe.exec(doc.slice(ls, selStart))
  if (m === null) return null
  const [, ws, marker, inner] = m
  const gfm = `${ws}${marker} [${inner.toLowerCase() === 'x' ? 'x' : ' '}] `
  return { from: ls, to: selStart, insert: gfm, selection: ls + gfm.length }
}

/** One source for every auto-pair: `close` is the single closer; `multi` is the doubled closer for
 *  the two-char markdown delimiters (`**`,`__`,`` `` ``,`((`,`[[`). Drives auto-pair AND auto-delete. */
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

/** Auto-close pairs on type. Multi-char (`**`,`__`,`` `` ``,`((`,`[[`) trigger on the second char;
 *  single `(`/`{` always pair; single `[` only at line start / after whitespace (so `-[` flows). */
export function autoPair(doc: string, selStart: number, selEnd: number, inserted: string): Edit | null {
  if (selStart !== selEnd) return null
  const c = selStart
  if (isInsideCode(c, doc)) return null
  const prev = doc[c - 1]
  const pair = PAIRS[inserted]
  if (!pair) return null

  if (pair.multi && prev === inserted) {
    // If the opener already auto-paired a single closer to the right (`[|]` → typing `[`), consume
    // it so the result is `[[|]]`, not a stray `[[|]]]`.
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

/** Backspace between an empty matched pair → delete both halves. */
export function autoDelete(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd || selStart === 0) return null
  const close = PAIRS[doc[selStart - 1]]?.close
  if (close === undefined || doc[selStart] !== close) return null
  return { from: selStart - 1, to: selStart + 1, insert: '', selection: selStart - 1 }
}

/** Enter while the caret sits between a matched pair → jump past the closer instead of inserting
 *  a newline (double-jump for `[[ ]]`). Runs before list/blockquote continuation in the caller, so
 *  a caret between an empty pair always jumps rather than opening a new item. */
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

/** Input-time dash + arrow auto-format. Fires on the NEXT char so collisions resolve first;
 *  skips inside code. `--`<non-dash> → em; `<-`/`->`/`<->` → arrows; `-` next to `–` → em. */
export function dashArrow(doc: string, selStart: number, selEnd: number, inserted: string): Edit | null {
  if (selStart !== selEnd || inserted.length !== 1) return null
  const c = selStart
  if (isInsideCode(c, doc)) return null

  // em-dash: "--" then a non-dash char (preserve --- HR via the 3-back check)
  if (inserted !== '-' && c >= 2 && doc[c - 1] === '-' && doc[c - 2] === '-' && doc[c - 3] !== '-') {
    return { from: c - 2, to: c, insert: `—${inserted}`, selection: c }
  }
  // en→em promotion: typing '-' adjacent to an existing en-dash
  if (inserted === '-' && doc[c - 1] === '–') return { from: c - 1, to: c, insert: '—', selection: c }
  // arrows on '>'
  if (inserted === '>') {
    if (doc[c - 1] === '←') return { from: c - 1, to: c, insert: '↔', selection: c }
    if (doc[c - 1] === '-') return { from: c - 1, to: c, insert: '→', selection: c }
  }
  // '<-' → '←' on the '-'
  if (inserted === '-' && doc[c - 1] === '<') return { from: c - 1, to: c, insert: '←', selection: c }
  // en-dash: a second space in " - " (non-whitespace must precede the dash; skip inside wikilinks)
  if (inserted === ' ' && c >= 2 && doc[c - 1] === '-' && doc[c - 2] === ' ') {
    const ls = lineStartAt(doc, c)
    const before = doc.slice(ls, c - 2)
    if (/\S/.test(before) && !isInsideWikilink(c, doc)) {
      return { from: c - 1, to: c, insert: '– ', selection: c + 1 }
    }
  }
  return null
}
