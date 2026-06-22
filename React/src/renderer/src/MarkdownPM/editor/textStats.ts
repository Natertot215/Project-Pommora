export interface TextStats {
  lines: number
  words: number
  chars: number
}

// Lines count raw source; words/chars count rendered prose (markdown syntax stripped).
export function textStats(body: string): TextStats {
  const lines = body === '' ? 0 : body.split('\n').length
  const prose = body
    .replace(/```[\s\S]*?```/g, '') // fenced code blocks
    .replace(/^[ \t]*#{1,6}[ \t]+/gm, '') // heading markers
    .replace(/^[ \t]*>[ \t]?/gm, '') // blockquote markers
    .replace(/^[ \t]*(?:[-*+•]|\d+\.)[ \t]+(?:\[[ xX]?\][ \t]+)?/gm, '') // list / task markers
    .replace(/\[\[([^\]\r\n]*)\]\]/g, '$1') // wikilinks → title
    .replace(/!?\[([^\]\r\n]*)\]\([^)\r\n]*\)/g, '$1') // links / images → text
    .replace(/\*\*|__|~~|\*|_|`/g, '') // inline emphasis + code
    .trim()
  const words = prose === '' ? 0 : prose.split(/\s+/).length
  const chars = prose.replace(/\s/g, '').length
  return { lines, words, chars }
}
