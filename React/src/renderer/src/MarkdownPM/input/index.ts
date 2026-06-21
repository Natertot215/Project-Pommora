// Pure typing transforms. Each takes the document + selection (+ the char being inserted, for
// the keystroke-reactive ones) and returns an Edit to apply, or null to fall through to the
// default. Framework-free: the CM6 keymap (Phase 4) wires these in as one atomic transaction
// with a re-entry guard. Input-time only — paste preserves literal text by construction (these
// fire on single-char insert / specific keys).
import { isInsideCode, isInsideWikilink } from '../parser'

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

// A list line: indent, marker (ordered or bullet) + optional task bracket + required space, content.
const listMarkerRe = /^(\s*)((?:\d+\.|[-*+•])(?:[ \t]*\[[ xX]?\])?[ \t]+)(.*)$/
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
  const m = listMarkerRe.exec(line)
  if (m === null) return null
  const [, indent, marker] = m
  if (selStart < ls + indent.length + marker.length) return null // caret in/before the marker zone

  const ordered = /^(\d+)\./.exec(marker.trimStart())
  let next = ordered ? `${parseInt(ordered[1], 10) + 1}. ` : `${marker.trimStart()[0]} `
  if (/\[[ xX]\]/.test(marker)) next = `${next.trimEnd()} [ ] ` // continue checkboxes as fresh unchecked
  const insert = `\n${indent}${next}`
  return { from: selStart, to: selStart, insert, selection: selStart + insert.length }
}

// A blockquote line's marker prefix (one or more `>`, each with an optional space; nesting kept).
const blockquotePrefixRe = /^[ \t]*(?:>[ \t]?)+/

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

/** The deepest list nesting Tab will create (spec §6.2). */
const MAX_NESTING_LEVEL = 3

/** Tab on a list line → insert one tab at line start (nest a level), capped at the max nesting.
 *  Level = tabCount + ⌊spaceCount/2⌋ (mirrors the renderer). Non-list lines / selections fall
 *  through (return null) so Tab keeps its default behavior elsewhere. */
export function indentListOnTab(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd) return null
  const ls = lineStartAt(doc, selStart)
  const m = listMarkerRe.exec(doc.slice(ls, lineEndAt(doc, selStart)))
  if (m === null) return null
  const indent = m[1]
  const level = (indent.match(/\t/g)?.length ?? 0) + Math.floor((indent.match(/ /g)?.length ?? 0) / 2)
  if (level >= MAX_NESTING_LEVEL) return null
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

const MULTI_PAIR: Record<string, string> = { '*': '**', _: '__', '`': '``', '(': '))', '[': ']]' }
const SINGLE_PAIR: Record<string, string> = { '(': ')', '{': '}' }

/** Auto-close pairs on type. Multi-char (`**`,`__`,`` `` ``,`((`,`[[`) trigger on the second char;
 *  single `(`/`{` always pair; single `[` only at line start / after whitespace (so `-[` flows). */
export function autoPair(doc: string, selStart: number, selEnd: number, inserted: string): Edit | null {
  if (selStart !== selEnd) return null
  const c = selStart
  if (isInsideCode(c, doc)) return null
  const prev = doc[c - 1]

  if (inserted in MULTI_PAIR && prev === inserted) {
    const close = MULTI_PAIR[inserted]
    return { from: c, to: c, insert: inserted + close, selection: c + 1 }
  }
  if (inserted === '[') {
    const atLineStart = c === lineStartAt(doc, c)
    if (atLineStart || prev === ' ' || prev === '\t' || prev === '\n') {
      return { from: c, to: c, insert: '[]', selection: c + 1 }
    }
    return null
  }
  if (inserted === '(' || inserted === '{') {
    return { from: c, to: c, insert: inserted + SINGLE_PAIR[inserted], selection: c + 1 }
  }
  return null
}

const DELETE_PAIR: Record<string, string> = { '*': '*', _: '_', '`': '`', '(': ')', '[': ']' }

/** Backspace between an empty matched pair → delete both halves. */
export function autoDelete(doc: string, selStart: number, selEnd: number): Edit | null {
  if (selStart !== selEnd || selStart === 0) return null
  const open = doc[selStart - 1]
  if (!(open in DELETE_PAIR) || doc[selStart] !== DELETE_PAIR[open]) return null
  return { from: selStart - 1, to: selStart + 1, insert: '', selection: selStart - 1 }
}

/** Enter while the caret sits between a matched pair on the line → jump past the closer instead
 *  of inserting a newline (double-jump for `[[ ]]`). Carve-out: a list-marker checkbox falls
 *  through to list continuation (caller order handles that). */
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
