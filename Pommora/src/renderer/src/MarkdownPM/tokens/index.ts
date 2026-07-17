// Emphasis is located on the mdast AST so `_`/`*` mixing/nesting is correct and code spans never emit emphasis.
import type { Root, RootContent, PhrasingContent } from 'mdast'
import { parse, isInsideCode } from '../parser'
import {
  isInlineMathContent,
  imageEmbedRegex,
  markdownLinkRegex,
  inlineCodeRegex,
  blockLatexRegex,
  inlineLatexRegex,
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
  contentRange: [number, number]
  markerRanges: [number, number][]
}

type Span = [number, number]
const overlaps = (a: Span, b: Span): boolean => a[0] < b[1] && b[0] < a[1]

const notOverlapping =
  (claimed: Token[]) =>
  (tk: Token): boolean =>
    !claimed.some((c) => overlaps(c.range, tk.range))

type MdNode = Root | RootContent | PhrasingContent

function childSpan(node: MdNode): Span | null {
  const kids = 'children' in node ? node.children : undefined
  if (!kids || kids.length === 0) return null
  const start = kids[0].position?.start.offset
  const end = kids[kids.length - 1].position?.end.offset
  return start != null && end != null ? [start, end] : null
}

// Marker spans come from the tighter of (delimiter width) and (child span), robust when an inner node abuts the run.
function pushEmphasis(
  node: MdNode,
  kind: 'italic' | 'bold' | 'strikethrough',
  width: number,
  out: Token[],
): void {
  const fs = node.position?.start.offset
  const fe = node.position?.end.offset
  if (fs == null || fe == null || fe - fs < width * 2) return
  const cs = childSpan(node) ?? [fs + width, fe - width]
  const contentStart = Math.max(cs[0], fs + width)
  const contentEnd = Math.min(cs[1], fe - width)
  if (contentEnd <= contentStart) return
  out.push({
    kind,
    range: [fs, fe],
    contentRange: [contentStart, contentEnd],
    markerRanges: [
      [contentStart - width, contentStart],
      [contentEnd, contentEnd + width],
    ],
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

interface RegexSpec {
  kind: TokenKind
  re: RegExp
  open: number
  close: number
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
        [content[1], fe],
      ],
    })
  }
  return tokens
}

// No `d` flag, so offsets are derived from the known `[[` prefix.
function wikiLinkTokens(text: string): Token[] {
  const tokens: Token[] = []
  for (const m of text.matchAll(pageLinkPattern())) {
    if (m.index == null) continue
    const fs = m.index
    const fe = fs + m[0].length
    if (isInsideCode(fs, text)) continue
    const contentStart = fs + 2
    const contentEnd = contentStart + (m[1]?.length ?? 0)
    tokens.push({
      kind: 'wikiLink',
      range: [fs, fe],
      contentRange: [contentStart, contentEnd],
      markerRanges: [
        [fs, fs + 2],
        [fe - 2, fe],
      ],
    })
  }
  return tokens
}

export function tokenize(text: string): Token[] {
  const ast = parse(text)
  const tokens: Token[] = []
  walkEmphasis(ast, tokens)

  // Code tokenizes FIRST so connections and links inside `spans` are dropped like latex already is —
  // a [[link]] in code must render (and click) as literal code, not a live connection.
  const code = regexTokens(text, { kind: 'inlineCode', re: inlineCodeRegex(), open: 1, close: 1 })
  const images = regexTokens(text, {
    kind: 'imageEmbed',
    re: imageEmbedRegex(),
    open: 3,
    close: 2,
  })
  const wikis = wikiLinkTokens(text).filter(notOverlapping([...images, ...code]))
  const links = regexTokens(text, {
    kind: 'link',
    re: markdownLinkRegex(),
    open: 1,
    close: 1,
  }).filter(notOverlapping([...images, ...wikis, ...code]))
  const blockTex = regexTokens(text, {
    kind: 'blockLatex',
    re: blockLatexRegex(),
    open: 2,
    close: 2,
  }).filter(notOverlapping(code))
  const inlineTex = regexTokens(text, {
    kind: 'inlineLatex',
    re: inlineLatexRegex(),
    open: 1,
    close: 1,
    accept: isInlineMathContent,
  }).filter(notOverlapping([...code, ...blockTex]))

  tokens.push(...images, ...wikis, ...links, ...code, ...blockTex, ...inlineTex)
  tokens.sort((a, b) => a.range[0] - b.range[0])
  return tokens
}

// A caret at a wikilink's `end` does NOT activate it (the closing `]]` was passed).
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
