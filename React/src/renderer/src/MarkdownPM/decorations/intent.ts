// Decoration-intent mapping — still framework-free. Turns detected tokens + caret state into a
// flat list of intents (which Styles.css class, which marker ranges to hide, which widget to
// draw + its data). The CM6 adapter (editor/decorations) is the ONLY thing that converts these
// into real CM6 decorations; keeping this layer pure data means it's unit-testable without an
// editor and the behavior layer never holds a CSS literal — only class names + widget specs.
import type { Token, TokenKind } from '../tokens'
import { isThematicBreakLine, isHeadingLine, isDashBulletLine, isOrderedListLine, hasCheckbox } from '../detect'

const HEADING_RE = /^(\s{0,3})(#{1,6})([ \t]+)(.*)$/
const BULLET_RE = /^([ \t]*)(-[ \t]+)/
const ORDERED_RE = /^([ \t]*)(\d+)\.[ \t]+/
const CHECKBOX_RE = /^([ \t]*)[-*+][ \t]*(\[[ xX]\])[ \t]+/d

/** Source-indent → visual nesting level (`level = tabs + ⌊spaces/2⌋`, capped at 3 — spec §6.2). */
function indentLevel(ws: string): number {
  let tabs = 0
  let spaces = 0
  for (const ch of ws) ch === '\t' ? tabs++ : spaces++
  return Math.min(3, tabs + Math.floor(spaces / 2))
}

/** A widget to draw in place of source text, with the data its renderer needs. */
export type WidgetSpec =
  | { type: 'hr' }
  | { type: 'bullet' }
  | { type: 'ordered'; label: string }
  | { type: 'checkbox'; bracketFrom: number; bracketTo: number; checked: boolean }

export type DecoIntent =
  | { kind: 'class'; from: number; to: number; className: string }
  | { kind: 'hide'; from: number; to: number }
  | { kind: 'widget'; from: number; to: number; spec: WidgetSpec }
  /** A whole-line decoration (`from` = line start). Carries the list nesting level so the
   *  stylesheet can apply per-level indent + the hanging indent that flushes wrapped lines. */
  | { kind: 'line'; from: number; className: string; level: number }

/** Inline token kind → the Styles.css class applied to its content. */
const CONTENT_CLASS: Partial<Record<TokenKind, string>> = {
  bold: 'md-bold',
  italic: 'md-italic',
  strikethrough: 'md-strike',
  inlineCode: 'md-code',
  link: 'md-link',
  wikiLink: 'md-connection',
  imageEmbed: 'md-image',
  inlineLatex: 'md-latex',
  blockLatex: 'md-latex'
}

/**
 * Build the decoration intents for a document.
 * - Inline tokens: a content class always; markers hidden unless the token is active (caret on it).
 * - Headings: a size class on the title + the `#` markers hidden caret-out.
 * - Lists/checkboxes: always-show glyph widgets (• / a checkbox box) over the source marker.
 * - HR: a rule widget caret-out; literal `---` when the caret is on the line.
 */
export function decorationsFor(text: string, tokens: Token[], active: Set<number>, selStart: number): DecoIntent[] {
  const intents: DecoIntent[] = []

  tokens.forEach((tk, i) => {
    const cls = CONTENT_CLASS[tk.kind]
    if (cls) intents.push({ kind: 'class', from: tk.contentRange[0], to: tk.contentRange[1], className: cls })
    if (!active.has(i)) {
      for (const [s, e] of tk.markerRanges) intents.push({ kind: 'hide', from: s, to: e })
    }
  })

  let pos = 0
  for (const line of text.split('\n')) {
    const ls = pos
    const le = pos + line.length
    const caretOnLine = selStart >= ls && selStart <= le

    if (isHeadingLine(line)) {
      const hm = HEADING_RE.exec(line)
      if (hm) {
        const level = hm[2].length
        const contentStart = ls + hm[1].length + hm[2].length + hm[3].length
        // Size the WHOLE line so the `#` markers grow/shrink with the level too (live, as typed).
        intents.push({ kind: 'class', from: ls, to: le, className: `md-h${level}` })
        // The `#` markers render muted (label-secondary) when visible; hidden when the caret leaves.
        if (contentStart > ls) intents.push({ kind: 'class', from: ls, to: contentStart, className: 'md-hmarker' })
        if (!caretOnLine) intents.push({ kind: 'hide', from: ls, to: contentStart })
      }
    } else if (hasCheckbox(line)) {
      const cm = CHECKBOX_RE.exec(line)
      const bracket = cm?.indices?.[2]
      if (cm && bracket) {
        const [bs, be] = bracket
        // Replace the whole prefix (indent + marker) so nesting comes purely from the line's
        // padding, never literal leading whitespace — keeps the hanging indent exact.
        intents.push({ kind: 'line', from: ls, className: 'md-li', level: indentLevel(cm[1]) })
        intents.push({
          kind: 'widget',
          from: ls,
          to: ls + cm[0].length,
          spec: { type: 'checkbox', bracketFrom: ls + bs, bracketTo: ls + be, checked: cm[2][1].toLowerCase() === 'x' }
        })
      }
    } else if (isDashBulletLine(line)) {
      const bm = BULLET_RE.exec(line)
      if (bm) {
        intents.push({ kind: 'line', from: ls, className: 'md-li', level: indentLevel(bm[1]) })
        intents.push({ kind: 'widget', from: ls, to: ls + bm[0].length, spec: { type: 'bullet' } })
      }
    } else if (isOrderedListLine(line)) {
      const om = ORDERED_RE.exec(line)
      if (om) {
        intents.push({ kind: 'line', from: ls, className: 'md-li', level: indentLevel(om[1]) })
        intents.push({ kind: 'widget', from: ls, to: ls + om[0].length, spec: { type: 'ordered', label: `${om[2]}.` } })
      }
    } else if (isThematicBreakLine(line) && !caretOnLine) {
      intents.push({ kind: 'widget', from: ls, to: le, spec: { type: 'hr' } })
    }
    pos = le + 1
  }

  return intents
}
