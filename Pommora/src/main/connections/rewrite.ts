// Pure title rewrite over a body: replace every `[[oldTitle]]` (case-insensitive
// normalized match; legacy `[[old|id]]` tolerated → id dropped) with `[[newTitle]]`.
// The rename-cascade primitive. Mirrors Swift's ConnectionRewriter (shares the pattern).

import { normalizeTitle, pageLinkPattern } from '@shared/connections'

/** Rewrite every connection to `oldTitle` (normalized) as a connection to `newTitle`.
 *  Non-matching links and `![[ ]]` embeds are left untouched. Pure (string → string). */
export function rewriteConnections(body: string, oldTitle: string, newTitle: string): string {
  const oldKey = normalizeTitle(oldTitle)
  return body.replace(pageLinkPattern(), (match, title: string) =>
    normalizeTitle(title) === oldKey ? `[[${newTitle}]]` : match,
  )
}
