// The token model + the tokenizer. Emphasis (bold/italic) is located on the mdast AST so
// `_`/`*` mixing + nesting is correct and code spans never emit emphasis; the other inline
// constructs are regex-located (cheap, exact). Plus active-token computation: which tokens
// have the caret/selection on them (so their markers reveal). Pure — no CM6.
import type { Root, RootContent, PhrasingContent } from 'mdast'
import { parse, isInsideCode } from '../parser'
import {
  isInlineMathContent,
  imageEmbedRegex,
  markdownLinkRegex,
  inlineCodeRegex,
  blockLatexRegex,
  inlineLatexRegex
} from '../detect'
import { pageLinkPattern } from '@shared/connections'

export type TokenKind =
  | 'italic'
  | 'bold'
  | 'strikethrough'
  | 'inlineCode'
  | 'blockLatex'
  | 'inlineLatex'
  | 'imageEmbed'
  | 'wikiLink'
  | 'link'

export interface Token {
  kind: TokenKind
  /** Full span incl. markers, `[start, end)`. */
  range: [number, number]
  /** Inner content span. */
  contentRange: [number, number]
  /** The delimiter spans (open/close, etc.). */
  markerRanges: [number, number][]
}

type Span = [number, number]
const overlaps = (a: Span, b: Span): boolean => a[0] < b[1] && b[0] < a[1]

/** Drop tokens whose range overlaps any of the higher-priority `claimed` tokens. */
const notOverlapping = (claimed: Token[]) => (tk: Token): boolean =>
  !claimed.some((c) => overlaps(c.range, tk.range))

// --- Emphasis (mdast) ----------------------------------------------------------------------

type MdNode = Root | RootContent | PhrasingContent

/** Union of a node's direct children offsets (the "real" content span). */
function childSpan(node: MdNode): Span | null {
  const kids = 'children' in node ? node.children : undefined
  if (!kids || kids.length === 0) return null
  const start = kids[0].position?.start.offset
  const end = kids[kids.length - 1].position?.end.offset
  return start != null && end != null ? [start, end] : null
}

/** Emit one emphasis token, reconstructing marker spans from the tighter of (delimiter width)
 *  and (child span) — robust when an inner node abuts the outer delimiter run. */
function pushEmphasis(node: MdNode, kind: 'italic' | 'bold' | 'strikethrough', width: number, out: Token[]): void {
  const fs = node.position?.start.offset
  const fe = node.position?.end.offset
  if (fs == null || fe == null || fe - fs < width * 2) return
  const cs = childSpan(node) ?? [fs + width, fe - width]
  // Clamp the content span inside the delimiters; the marker spans then fall out of the
  // clamp (openStart ≥ fs and closeStart + width ≤ fe hold by construction).
  const contentStart = Math.max(cs[0], fs + width)
  const contentEnd = Math.min(cs[1], fe - width)
  if (contentEnd <= contentStart) return
  out.push({
    kind,
    range: [fs, fe],
    contentRange: [contentStart, contentEnd],
    markerRanges: [
      [contentStart - width, contentStart],
      [contentEnd, contentEnd + width]
    ]
  })
}

function walkEmphasis(node: MdNode, out: Token[]): void {
  if (node.type === 'emphasis') pushEmphasis(node, 'italic', 1, out)
  else if (node.type === 'strong') pushEmphasis(node, 'bold', 2, out)
  else if (node.type === 'delete') pushEmphasis(node, 'strikethrough', 2, out)
  if ('children' in node && node.children) {
    for (const child of node.children) walkEmphasis(child as MdNode, out)
  }
}

// --- Inline regex tokens -------------------------------------------------------------------

interface RegexSpec {
  kind: TokenKind
  re: RegExp
  /** Open/close marker lengths to carve off the full match. */
  open: number
  close: number
  /** Optional content-level gate (e.g. inline-math heuristic). */
  accept?: (content: string) => boolean
}

function regexTokens(text: string, spec: RegexSpec): Token[] {
  const tokens: Token[] = []
  for (const m of text.matchAll(spec.re)) {
    const indices = m.indices
    const fullSpan = indices?.[0]
    if (!fullSpan) continue
    const [fs, fe] = fullSpan
    const content: Span = indices[1] ?? [fs + spec.open, fe - spec.close]
    if (spec.accept && !spec.accept(m[1] ?? '')) continue
    if (isInsideCode(fs, text)) continue
    tokens.push({
      kind: spec.kind,
      range: [fs, fe],
      contentRange: [content[0], content[1]],
      markerRanges: [
        [fs, content[0]],
        [content[1], fe]
      ]
    })
  }
  return tokens
}

/** Wikilinks via the shared connections pattern (no `d` flag, so offsets are derived from the
 *  known `[[` prefix). Title-only; `![[ ]]` excluded by the pattern's lookbehind. */
function wikiLinkTokens(text: string): Token[] {
  const tokens: Token[] = []
  for (const m of text.matchAll(pageLinkPattern())) {
    if (m.index == null) continue
    const fs = m.index
    const fe = fs + m[0].length
    if (isInsideCode(fs, text)) continue
    const contentStart = fs + 2 // after "[["
    const contentEnd = contentStart + (m[1]?.length ?? 0)
    tokens.push({
      kind: 'wikiLink',
      range: [fs, fe],
      contentRange: [contentStart, contentEnd],
      markerRanges: [
        [fs, fs + 2],
        [fe - 2, fe]
      ]
    })
  }
  return tokens
}

export function tokenize(text: string): Token[] {
  const ast = parse(text)
  const tokens: Token[] = []
  walkEmphasis(ast, tokens)

  const images = regexTokens(text, { kind: 'imageEmbed', re: imageEmbedRegex(), open: 3, close: 2 })
  const wikis = wikiLinkTokens(text).filter(notOverlapping(images))
  const links = regexTokens(text, { kind: 'link', re: markdownLinkRegex(), open: 1, close: 1 }).filter(
    notOverlapping([...images, ...wikis])
  )
  const code = regexTokens(text, { kind: 'inlineCode', re: inlineCodeRegex(), open: 1, close: 1 })
  const blockTex = regexTokens(text, { kind: 'blockLatex', re: blockLatexRegex(), open: 2, close: 2 }).filter(
    notOverlapping(code)
  )
  const inlineTex = regexTokens(text, {
    kind: 'inlineLatex',
    re: inlineLatexRegex(),
    open: 1,
    close: 1,
    accept: isInlineMathContent
  }).filter(notOverlapping([...code, ...blockTex]))

  tokens.push(...images, ...wikis, ...links, ...code, ...blockTex, ...inlineTex)
  tokens.sort((a, b) => a.range[0] - b.range[0])
  return tokens
}

// --- Active tokens (caret/selection) -------------------------------------------------------

/** Which tokens have the caret/selection on them (so their markers should reveal). A caret
 *  inside `[start, end]` activates; at a wikilink's `end` it does NOT (the closing `]]` was
 *  passed); a non-empty selection intersecting a token activates it. */
export function activeTokenIndices(tokens: Token[], selStart: number, selEnd: number): Set<number> {
  const active = new Set<number>()
  tokens.forEach((tk, i) => {
    const [s, e] = tk.range
    if (selStart !== selEnd) {
      if (selStart < e && s < selEnd) active.add(i)
      return
    }
    const caret = selStart
    if (caret === e && tk.kind === 'wikiLink') return
    if (caret >= s && caret <= e) active.add(i)
  })
  return active
}
