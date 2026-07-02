import { fromMarkdown } from "mdast-util-from-markdown";
import { gfm } from "micromark-extension-gfm";
import { gfmFromMarkdown } from "mdast-util-gfm";
import type { Root } from "mdast";

export function parse(text: string): Root {
  return fromMarkdown(text, { extensions: [gfm()], mdastExtensions: [gfmFromMarkdown()] });
}

// Inline-span membership, line-local. A span opens with a run of N backticks and closes with a matching
// run; the marker positions themselves are boundaries, NOT interior — so typing the closing backtick of
// `code|` still type-overs. An UNCLOSED opener counts as inside for the rest of the line: while a span is
// being typed it's always unclosed, and that's exactly when transforms must already stay out.
function insideInlineSpan(line: string, col: number): boolean {
  let i = 0;
  while (i < line.length) {
    if (line[i] !== "`") {
      i++;
      continue;
    }
    let openLen = 1;
    while (line[i + openLen] === "`") openLen++;
    const contentStart = i + openLen;
    let j = contentStart;
    let closeStart = -1;
    while (j < line.length) {
      if (line[j] !== "`") {
        j++;
        continue;
      }
      let runLen = 1;
      while (line[j + runLen] === "`") runLen++;
      if (runLen === openLen) {
        closeStart = j;
        break;
      }
      j += runLen;
    }
    if (closeStart === -1) return col >= contentStart;
    if (col >= contentStart && col < closeStart) return true;
    i = closeStart + openLen;
  }
  return false;
}

const FENCE_OPEN = /^\s*(```|~~~)/;

// An offset on a fence line counts as inside (the fence is part of the construct). Fences pair by marker
// character (a ~~~ line inside a ``` block is content, and vice versa); outside fences, inline `spans`
// count as code too.
export function isInsideCode(offset: number, text: string): boolean {
  let pos = 0;
  let fence: "`" | "~" | null = null;
  for (const line of text.split("\n")) {
    const lineEnd = pos + line.length;
    const marker = FENCE_OPEN.exec(line)?.[1][0] as "`" | "~" | undefined;
    if (marker && (fence === null || fence === marker)) {
      if (offset >= pos && offset <= lineEnd) return true;
      fence = fence === null ? marker : null;
    } else if (offset >= pos && offset <= lineEnd) {
      return fence !== null || insideInlineSpan(line, offset - pos);
    }
    pos = lineEnd + 1;
  }
  return false;
}

// Line-scoped so an unclosed `[[` never bleeds across lines.
export function isInsideWikilink(offset: number, text: string): boolean {
  const lineStart = text.lastIndexOf("\n", Math.max(0, offset - 1)) + 1;
  let depth = 0;
  let i = lineStart;
  while (i < offset) {
    if (text[i] === "[" && text[i + 1] === "[") {
      depth++;
      i += 2;
    } else if (text[i] === "]" && text[i + 1] === "]") {
      depth = Math.max(0, depth - 1);
      i += 2;
    } else {
      i++;
    }
  }
  return depth > 0;
}
