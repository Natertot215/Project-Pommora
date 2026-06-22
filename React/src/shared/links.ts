// External markdown-link URL handling. No fs, no React — imported by both main (the opener) and the
// renderer (the decoration that styles valid vs invalid), so a link's appearance can never disagree
// with whether it actually opens.

/** Schemeless URLs get `https://`; anything with a scheme is left as-is. */
export function normalizeLinkUrl(url: string): string {
  const u = url.trim()
  return /^[a-z][a-z0-9+.-]*:/i.test(u) ? u : `https://${u}`
}

/** A statically-openable link: a well-formed http(s) URL with a dotted host, or a plausible mailto.
 *  No network — this is the local check that mirrors how connections resolve against the index. */
export function isValidLink(url: string): boolean {
  const u = url.trim()
  if (!u || /\s/.test(u)) return false
  const n = normalizeLinkUrl(u)
  if (/^mailto:/i.test(n)) return /^mailto:[^\s@]+@[^\s@]+\.[^\s@]+$/i.test(n)
  if (!/^https?:\/\//i.test(n)) return false
  try {
    const host = new URL(n).hostname
    return host.length > 2 && host.includes('.') && !host.startsWith('.') && !host.endsWith('.')
  } catch {
    return false
  }
}
