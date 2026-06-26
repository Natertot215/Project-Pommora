// Inline matchers return a fresh /g regex per call so callers never share lastIndex.
import { parse } from '../parser'

export const imageEmbedRegex = (): RegExp => /!\[\[([^\]\r\n]*)\]\]/gd
export const markdownLinkRegex = (): RegExp => /\[([^\]\r\n]+)\]\(([^)\r\n]+)\)/gd
export const inlineCodeRegex = (): RegExp => /`([^`\n]+)`/gd
export const blockLatexRegex = (): RegExp => /(?<!\$)\$\$([\s\S]+?)\$\$/gd
export const inlineLatexRegex = (): RegExp => /(?<!\$)\$(?!\$)([^$\n]+?)\$(?!\$)/gd

export const blockquotePrefixRe = /^[ \t]*(?:>[ \t]?)+/

export const MAX_NESTING_LEVEL = 3

export function indentLevel(ws: string): number {
  let tabs = 0
  let spaces = 0
  for (const ch of ws) ch === '\t' ? tabs++ : spaces++
  return Math.min(MAX_NESTING_LEVEL, tabs + Math.floor(spaces / 2))
}

/** The single list-marker parser. Every layer reads markers through this — never its own regex.
 *  `kind` is `checkbox` only when a non-empty box follows a `-`/`*`/`+` bullet (`1. [ ]` stays `ordered`).
 *  `arrow` is the `→ ` list (typed `-> `, auto-converted to the glyph by `dashArrow`); it behaves like a
 *  bullet but its marker IS the on-disk glyph, so it's kept as literal source rather than widget-swapped. */
export interface ListMarker {
  kind: 'ordered' | 'bullet' | 'checkbox' | 'arrow'
  bullet?: string
  digits?: string
  level: number
  markerStart: number
  markerEnd: number
  contentStart: number
  box?: { start: number; end: number; inner: string }
  checked?: boolean
}

const LIST_MARKER_RE = /^([ \t]*)(?:(\d+)\.|([-*+•]))(?:[ \t]*(\[([ xX]?)\]))?([ \t]+)(.*)$/d
const ARROW_MARKER_RE = /^([ \t]*)→([ \t]+)/

export function parseListMarker(line: string): ListMarker | null {
  const arrow = ARROW_MARKER_RE.exec(line)
  if (arrow) {
    const markerStart = arrow[1].length
    return {
      kind: 'arrow',
      bullet: '→',
      level: indentLevel(arrow[1]),
      markerStart,
      markerEnd: markerStart + 1,
      contentStart: markerStart + 1 + arrow[2].length
    }
  }
  const m = LIST_MARKER_RE.exec(line)
  const idx = m?.indices
  const ws = idx?.[6]
  if (!m || !idx || !ws) return null
  const indent = m[1]
  const markerStart = indent.length
  const level = indentLevel(indent)
  const contentStart = ws[1]
  const b = idx[4]
  const box = b ? { start: b[0], end: b[1], inner: m[5] ?? '' } : undefined
  const bullet = m[3]

  if (bullet !== undefined && box && box.inner !== '' && '-*+'.includes(bullet)) {
    return { kind: 'checkbox', bullet, level, markerStart, markerEnd: box.end, contentStart, box, checked: box.inner !== ' ' }
  }
  if (m[2] !== undefined) {
    return { kind: 'ordered', digits: m[2], level, markerStart, markerEnd: markerStart + m[2].length + 1, contentStart, box }
  }
  return { kind: 'bullet', bullet, level, markerStart, markerEnd: markerStart + (bullet?.length ?? 1), contentStart, box }
}

const dashBulletRegex = /^([ \t]*)([-*+•](?:[ \t]*\[[ xX]?\])?[ \t]+)(.*)$/
const taskMarkerRegex = /^[ \t]*[-*+][ \t]*\[[ xX]\][ \t]+/
const headingPrefilter = /^[ ]{0,3}#{1,6}([ \t]|$)/
const blockquotePrefilter = /^[ \t]*>+[ \t]/

export function isThematicBreakLine(line: string): boolean {
  const t = line.trim()
  if (t.length < 3 || (t[0] !== '-' && t[0] !== '*' && t[0] !== '_')) return false
  return parse(line).children.some((n) => n.type === 'thematicBreak')
}

export function isHeadingLine(line: string): boolean {
  if (!headingPrefilter.test(line)) return false
  return parse(line).children.some((n) => n.type === 'heading')
}

/** Needs whitespace after the last `>`: `> a` and `>> a` activate; `>a`, `>>a`, bare `>` do not. */
export function isBlockquoteLine(line: string): boolean {
  if (!blockquotePrefilter.test(line)) return false
  return parse(line).children.some((n) => n.type === 'blockquote')
}

export function isDashBulletLine(line: string): boolean {
  const m = dashBulletRegex.exec(line)
  if (m === null) return false
  const marker = m[2]
  return marker.startsWith('-') && !marker.includes('[')
}

export function isOrderedListLine(line: string): boolean {
  return /^[ \t]*\d+\.[ \t]+/.test(line)
}

export function hasCheckbox(line: string): boolean {
  return taskMarkerRegex.test(line)
}

/** Inline-math gate: keeps prose / currency `$…$` from tokenizing as math. */
export function isInlineMathContent(content: string): boolean {
  if (/^[+-]?(\d{1,3}(?:,\d{3})*|\d+)(?:\.\d+)?$/.test(content)) return false // currency
  const mathyCount = (content.match(/[\\^_{}=+\-*/<>]/g) ?? []).length
  if (mathyCount === 0) return /^[A-Za-z]{1,3}$/.test(content)
  const tokens = content.split(/\s+/).filter(Boolean).length
  if (mathyCount >= 3) return tokens <= 120
  if (mathyCount === 2) return tokens <= 40
  return tokens <= 6
}
