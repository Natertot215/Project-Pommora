import { foldService, foldGutter, codeFolding, foldEffect, unfoldEffect, foldedRanges } from '@codemirror/language'
import { EditorView, type ViewUpdate } from '@codemirror/view'
import { Annotation, StateEffect, type Extension, type Text } from '@codemirror/state'
import { isHeadingLine } from '../detect'

/** Per-page fold persistence seam — reads/writes `.nexus/folds.json` via the host (kept Electron-free here). */
export interface FoldsApi {
  load: () => Promise<string[]>
  save: (keys: string[]) => void
}

/** Marks the mount-time re-apply of saved folds so the persist listener doesn't echo it straight back to disk. */
export const initialFoldAnnotation = Annotation.define<boolean>()

const HEADING_RE = /^(\s{0,3})(#{1,6})[ \t]+(.*)$/

export interface HeadingSection {
  /** Start of the heading line. */
  from: number
  /** End of the heading line's text — a fold begins here, so the heading itself stays visible. */
  lineEnd: number
  level: number
  /** Ordinal-disambiguated key for `.nexus/folds.json` (stable across heading-level changes). */
  key: string
  /** End of the section: the last line before the next equal-or-higher heading (or document end). */
  to: number
}

/** Every heading's foldable section. A section reaching no body lines is dropped (nothing to fold),
 *  but still consumes its ordinal so duplicate-text keys stay stable. */
export function headingSections(doc: string): HeadingSection[] {
  const lines = doc.split('\n')
  const starts: number[] = []
  for (let p = 0, i = 0; i < lines.length; i++) {
    starts.push(p)
    p += lines[i].length + 1
  }

  const heads: { idx: number; level: number; key: string }[] = []
  const seen = new Map<string, number>()
  for (let i = 0; i < lines.length; i++) {
    if (!isHeadingLine(lines[i])) continue
    const m = HEADING_RE.exec(lines[i])
    if (!m) continue
    const text = m[3].trim()
    const n = (seen.get(text) ?? 0) + 1
    seen.set(text, n)
    heads.push({ idx: i, level: m[2].length, key: n === 1 ? text : `${text} ${n}` })
  }

  const out: HeadingSection[] = []
  for (let h = 0; h < heads.length; h++) {
    const { idx, level, key } = heads[h]
    let endLine = lines.length - 1
    for (let n = h + 1; n < heads.length; n++) {
      if (heads[n].level <= level) {
        endLine = heads[n].idx - 1
        break
      }
    }
    const from = starts[idx]
    const lineEnd = from + lines[idx].length
    const to = starts[endLine] + lines[endLine].length
    if (to > lineEnd) out.push({ from, lineEnd, level, key, to })
  }
  return out
}

// Immutable doc → sections, so foldService/persistence don't re-scan the whole document per query.
const sectionCache = new WeakMap<Text, HeadingSection[]>()
function sectionsOf(doc: Text): HeadingSection[] {
  let s = sectionCache.get(doc)
  if (!s) {
    s = headingSections(doc.toString())
    sectionCache.set(doc, s)
  }
  return s
}

/** Fold effects to seed the editor with a page's saved folded headings (applied once at mount). */
export function initialFoldEffects(doc: Text, keys: string[]): StateEffect<unknown>[] {
  if (keys.length === 0) return []
  const wanted = new Set(keys)
  return sectionsOf(doc)
    .filter((s) => wanted.has(s.key))
    .map((s) => foldEffect.of({ from: s.lineEnd, to: s.to }))
}

function foldedKeys(doc: Text, folds: ReturnType<typeof foldedRanges>): string[] {
  const sections = sectionsOf(doc)
  const keys: string[] = []
  const it = folds.iter()
  for (; it.value !== null; it.next()) {
    const s = sections.find((x) => x.lineEnd === it.from)
    if (s) keys.push(s.key)
  }
  return keys
}

/** Heading folding: a chevron toggles each section closed/open; changes persist via `onFoldsChange`. */
export function markdownFolding(onFoldsChange: (keys: string[]) => void): Extension {
  const persist = EditorView.updateListener.of((u: ViewUpdate) => {
    const changed = u.transactions.some(
      (tr) => !tr.annotation(initialFoldAnnotation) && tr.effects.some((e) => e.is(foldEffect) || e.is(unfoldEffect))
    )
    if (changed) onFoldsChange(foldedKeys(u.state.doc, foldedRanges(u.state)))
  })

  return [
    codeFolding(),
    foldService.of((state, lineStart) => {
      const s = sectionsOf(state.doc).find((x) => x.from === lineStart)
      return s ? { from: s.lineEnd, to: s.to } : null
    }),
    foldGutter({
      markerDOM: (open) => {
        const el = document.createElement('span')
        el.className = `mdpm-fold-chevron${open ? ' open' : ''}`
        el.innerHTML =
          '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>'
        return el
      }
    }),
    persist
  ]
}
