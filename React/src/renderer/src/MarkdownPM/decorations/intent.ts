// Decoration-intent mapping — still framework-free. Turns detected tokens + caret state into a
// flat list of intents (which Styles.css class, which marker ranges to hide, which widget to
// draw). The CM6 adapter (Phase 2) is the ONLY thing that converts these into actual CM6
// decorations; keeping this layer pure data means it's unit-testable without an editor and the
// behavior layer never holds a CSS literal — only class names + widget tags.
import type { Token, TokenKind } from '../tokens'
import { isThematicBreakLine } from '../detect'

export type DecoIntent =
  | { kind: 'class'; from: number; to: number; className: string }
  | { kind: 'hide'; from: number; to: number }
  | { kind: 'widget'; from: number; to: number; widget: string }

/** Inline token kind → the Styles.css class applied to its content. */
const CONTENT_CLASS: Partial<Record<TokenKind, string>> = {
  bold: 'md-bold',
  italic: 'md-italic',
  inlineCode: 'md-code',
  link: 'md-link',
  wikiLink: 'md-connection',
  imageEmbed: 'md-image',
  inlineLatex: 'md-latex',
  blockLatex: 'md-latex'
}

/**
 * Build the decoration intents for a document.
 * - Inline tokens: a content class always; their markers are hidden unless the token is active
 *   (caret on it) — the dynamic-syntax reveal.
 * - Block constructs (HR for now): a widget when the caret is OFF the line, nothing when on it
 *   (so the literal `---` is editable).
 */
export function decorationsFor(
  text: string,
  tokens: Token[],
  active: Set<number>,
  selStart: number
): DecoIntent[] {
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
    if (isThematicBreakLine(line) && !caretOnLine) {
      intents.push({ kind: 'widget', from: ls, to: le, widget: 'hr' })
    }
    pos = le + 1
  }

  return intents
}
