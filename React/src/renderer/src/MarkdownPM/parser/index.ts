import { fromMarkdown } from 'mdast-util-from-markdown'
import { gfm } from 'micromark-extension-gfm'
import { gfmFromMarkdown } from 'mdast-util-gfm'
import type { Root } from 'mdast'

export function parse(text: string): Root {
  return fromMarkdown(text, { extensions: [gfm()], mdastExtensions: [gfmFromMarkdown()] })
}

// An offset on a fence line counts as inside (the fence is part of the construct).
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

// Line-scoped so an unclosed `[[` never bleeds across lines.
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
