// The parser seam — the ONLY place the behavior layer touches micromark/mdast. Everything
// downstream (detection, tokens, plain-text) consumes the AST shape this exposes, so the
// parser is swappable behind here. Plus the cheap line-scoped helper queries that detection
// + input transforms use to skip code / wikilink / latex regions without an AST walk.
import { fromMarkdown } from 'mdast-util-from-markdown'
import { gfm } from 'micromark-extension-gfm'
import { gfmFromMarkdown } from 'mdast-util-gfm'
import type { Root } from 'mdast'

/** Parse Markdown to a GFM mdast tree with per-node source offsets. */
export function parse(text: string): Root {
  return fromMarkdown(text, { extensions: [gfm()], mdastExtensions: [gfmFromMarkdown()] })
}

/** Is `offset` inside a fenced code block? Doc-scan toggling on ``` fence lines; an offset
 *  on a fence line counts as inside (the fence is part of the construct). */
export function isInsideCode(offset: number, text: string): boolean {
  let pos = 0
  let inFence = false
  for (const line of text.split('\n')) {
    const lineEnd = pos + line.length
    const isFence = /^\s*```/.test(line)
    if (isFence) {
      if (offset >= pos && offset <= lineEnd) return true
      inFence = !inFence
    } else if (offset >= pos && offset <= lineEnd) {
      return inFence
    }
    pos = lineEnd + 1
  }
  return false
}

/** Is `offset` inside a `[[ … ]]` wikilink? Line-scoped depth counter (+1 on `[[`, −1 floored
 *  on `]]`); inside iff depth > 0. Resets each line, so an unclosed `[[` never bleeds across. */
export function isInsideWikilink(offset: number, text: string): boolean {
  const lineStart = text.lastIndexOf('\n', Math.max(0, offset - 1)) + 1
  let depth = 0
  let i = lineStart
  while (i < offset) {
    if (text[i] === '[' && text[i + 1] === '[') {
      depth++
      i += 2
    } else if (text[i] === ']' && text[i + 1] === ']') {
      depth = Math.max(0, depth - 1)
      i += 2
    } else {
      i++
    }
  }
  return depth > 0
}

/** Is `offset` inside LaTeX? A `$$` block (doc-scan toggle on `$$`-only lines), or an open
 *  inline `$…$` on the offset's line (odd count of unescaped `$` before it). Approximate —
 *  LaTeX rendering is deferred; this only gates skip-guards. */
export function isInsideLatex(offset: number, text: string): boolean {
  let pos = 0
  let inBlock = false
  for (const line of text.split('\n')) {
    const lineEnd = pos + line.length
    const isBlockFence = line.trim() === '$$'
    if (isBlockFence) {
      if (offset >= pos && offset <= lineEnd) return true
      inBlock = !inBlock
    } else if (offset >= pos && offset <= lineEnd) {
      if (inBlock) return true
      let count = 0
      for (let j = pos; j < offset; j++) {
        if (text[j] === '$' && text[j - 1] !== '\\') count++
      }
      return count % 2 === 1
    }
    pos = lineEnd + 1
  }
  return false
}
