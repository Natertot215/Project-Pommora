import { gutter, GutterMarker, EditorView, Decoration, WidgetType, type ViewUpdate } from '@codemirror/view'
import {
  StateField,
  StateEffect,
  RangeSetBuilder,
  Annotation,
  type EditorState,
  type Extension,
  type Text,
  type Range
} from '@codemirror/state'
import { isHeadingLine } from '../detect'

/** Per-page fold persistence seam — reads/writes `.nexus/folds.json` via the host (kept Electron-free here). */
export interface FoldsApi {
  load: () => Promise<string[]>
  save: (keys: string[]) => void
}

/** Marks the mount-time re-apply of saved folds so the persist listener doesn't echo it straight back to disk. */
const initialFoldAnnotation = Annotation.define<boolean>()

const HEADING_RE = /^(\s{0,3})(#{1,6})[ \t]+(.*)$/

export interface HeadingSection {
  /** Start of the heading line. */
  from: number
  /** End of the heading line's text — the body to fold begins on the next line. */
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

const sectionCache = new WeakMap<Text, HeadingSection[]>()
function sectionsOf(doc: Text): HeadingSection[] {
  let s = sectionCache.get(doc)
  if (!s) {
    s = headingSections(doc.toString())
    sectionCache.set(doc, s)
  }
  return s
}

// ── Custom fold state ──────────────────────────────────────────────────────────
// CM6's native fold removes the body lines instantly. To mirror the sidebar's Reveal
// (grid 0fr↔1fr, 180ms), each fold is a block widget over the body lines whose own DOM
// animates; a per-frame requestMeasure keeps the lines below tracking the animated height.

type Phase = 'collapsing' | 'collapsed' | 'expanding'
interface FoldEntry {
  headingFrom: number
  from: number // first body line start
  to: number // last body line end
  phase: Phase
}

const foldEffect = StateEffect.define<{ headingFrom: number; from: number; to: number; animate: boolean }>()
const settleEffect = StateEffect.define<number>() // collapsing → collapsed (animation done)
const expandEffect = StateEffect.define<number>() // collapsed → expanding (start opening)
const dropEffect = StateEffect.define<number>() // expanding done → remove the fold

// Faithful clones of the folded body's line DOM, captured at fold time, keyed by heading start.
const cloneMap = new Map<number, HTMLElement>()

function lineElement(view: EditorView, pos: number): HTMLElement | null {
  let node: Node | null = view.domAtPos(pos).node
  while (node && !(node instanceof HTMLElement && node.classList.contains('cm-line'))) node = node.parentNode
  return node instanceof HTMLElement ? node : null
}

function cloneBody(view: EditorView, from: number, to: number): HTMLElement {
  const wrap = document.createElement('div')
  wrap.className = 'mdpm-fold-clone'
  const seen = new Set<HTMLElement>()
  for (let pos = from; pos <= to; ) {
    const line = view.state.doc.lineAt(pos)
    const el = lineElement(view, line.from)
    if (el && !seen.has(el)) {
      seen.add(el)
      wrap.appendChild(el.cloneNode(true))
    }
    if (line.to >= to) break
    pos = line.to + 1
  }
  return wrap
}

class RevealWidget extends WidgetType {
  constructor(
    readonly headingFrom: number,
    readonly phase: Phase
  ) {
    super()
  }
  eq(o: RevealWidget): boolean {
    return o.headingFrom === this.headingFrom && o.phase === this.phase
  }
  toDOM(view: EditorView): HTMLElement {
    const outer = document.createElement('div')
    outer.className = 'mdpm-fold-reveal'
    const inner = document.createElement('div')
    inner.className = 'mdpm-fold-reveal-inner'
    const clone = cloneMap.get(this.headingFrom)
    if (clone) inner.appendChild(clone.cloneNode(true))
    outer.appendChild(inner)

    if (this.phase === 'collapsed') {
      outer.style.gridTemplateRows = '0fr'
      return outer
    }
    const open = this.phase === 'expanding'
    outer.style.gridTemplateRows = open ? '0fr' : '1fr'
    const done = open ? dropEffect.of(this.headingFrom) : settleEffect.of(this.headingFrom)
    // Re-measure each frame so the lines below follow the animated height (CM6 only measures on update).
    const tick = (): void => {
      if (!outer.isConnected) return
      view.requestMeasure()
      requestAnimationFrame(tick)
    }
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        outer.style.gridTemplateRows = open ? '1fr' : '0fr'
        requestAnimationFrame(tick)
      })
    })
    outer.addEventListener(
      'transitionend',
      (e) => {
        if (e.propertyName === 'grid-template-rows') view.dispatch({ effects: done })
      },
      { once: true }
    )
    return outer
  }
  get estimatedHeight(): number {
    return -1
  }
  ignoreEvent(): boolean {
    return true
  }
}

const foldField = StateField.define<FoldEntry[]>({
  create: () => [],
  update(entries, tr) {
    let next: FoldEntry[] = tr.changes.empty
      ? entries
      : entries.map((e) => ({
          headingFrom: tr.changes.mapPos(e.headingFrom),
          from: tr.changes.mapPos(e.from, 1),
          to: tr.changes.mapPos(e.to, -1),
          phase: e.phase
        }))
    for (const ef of tr.effects) {
      if (ef.is(foldEffect)) {
        const v = ef.value
        next = next.filter((e) => e.headingFrom !== v.headingFrom)
        next = [...next, { headingFrom: v.headingFrom, from: v.from, to: v.to, phase: v.animate ? 'collapsing' : 'collapsed' }]
      } else if (ef.is(settleEffect)) {
        next = next.map((e) => (e.headingFrom === ef.value ? { ...e, phase: 'collapsed' } : e))
      } else if (ef.is(expandEffect)) {
        next = next.map((e) => (e.headingFrom === ef.value ? { ...e, phase: 'expanding' } : e))
      } else if (ef.is(dropEffect)) {
        cloneMap.delete(ef.value)
        next = next.filter((e) => e.headingFrom !== ef.value)
      }
    }
    return next
  },
  provide: (f) =>
    EditorView.decorations.from(f, (entries) => {
      const ranges: Range<Decoration>[] = []
      for (const e of entries) {
        ranges.push(Decoration.line({ class: 'md-h-folded' }).range(e.headingFrom))
        if (e.to > e.from) {
          ranges.push(Decoration.replace({ block: true, widget: new RevealWidget(e.headingFrom, e.phase) }).range(e.from, e.to))
        }
      }
      return Decoration.set(ranges, true)
    })
})

function toggleFold(view: EditorView, s: HeadingSection): void {
  const folded = view.state.field(foldField).some((e) => e.headingFrom === s.from)
  if (folded) {
    view.dispatch({ effects: expandEffect.of(s.from) })
    return
  }
  const bodyStart = s.lineEnd + 1
  if (bodyStart > s.to) return
  // A caret inside the body being folded becomes unplaced (blur) rather than jumping to the next visible line.
  const sel = view.state.selection.main
  const caretInBody = sel.to > s.lineEnd && sel.from <= s.to
  cloneMap.set(s.from, cloneBody(view, bodyStart, s.to))
  view.dispatch({ effects: foldEffect.of({ headingFrom: s.from, from: bodyStart, to: s.to, animate: true }) })
  if (caretInBody) view.contentDOM.blur()
}

// A chevron points down (open) when its section is unfolded or mid-expand, right when folding/folded.
function chevronOpen(state: EditorState, headingFrom: number): boolean {
  const e = state.field(foldField).find((x) => x.headingFrom === headingFrom)
  return !e || e.phase === 'expanding'
}

class ChevronMarker extends GutterMarker {
  // Chevron is a ::before on the gutter element. CM updates elementClass in place on the reused element,
  // so the rotation transitions even while the fold's requestMeasure loop keeps re-rendering content.
  readonly elementClass: string
  constructor(readonly open: boolean) {
    super()
    this.elementClass = `mdpm-fold-cell${open ? ' mdpm-fold-open' : ''}`
  }
  eq(o: ChevronMarker): boolean {
    return o.open === this.open
  }
  toDOM(): HTMLElement {
    return document.createElement('span')
  }
}

// Reserves the fold gutter's width on pages with no foldable headings. Without it the empty
// gutter collapses to 0 and the body text slides 20px left off --content-inset (the title's edge).
class SpacerMarker extends GutterMarker {
  toDOM(): HTMLElement {
    return document.createElement('span')
  }
}

const foldGutterExt = gutter({
  class: 'cm-foldGutter',
  initialSpacer: () => new SpacerMarker(),
  markers: (view) => {
    const b = new RangeSetBuilder<GutterMarker>()
    for (const s of sectionsOf(view.state.doc)) b.add(s.from, s.from, new ChevronMarker(chevronOpen(view.state, s.from)))
    return b.finish()
  },
  domEventHandlers: {
    mousedown(view, line, event) {
      if ((event as MouseEvent).button !== 0) return false
      const s = sectionsOf(view.state.doc).find((x) => x.from === line.from)
      if (!s) return false
      toggleFold(view, s)
      return true
    }
  }
})

/** Re-apply a page's saved folds at mount (no animation), capturing clones from the freshly-rendered lines. */
export function applySavedFolds(view: EditorView, keys: string[]): void {
  if (keys.length === 0) return
  const wanted = new Set(keys)
  const effects: StateEffect<unknown>[] = []
  for (const s of sectionsOf(view.state.doc)) {
    if (!wanted.has(s.key)) continue
    const bodyStart = s.lineEnd + 1
    if (bodyStart > s.to) continue
    cloneMap.set(s.from, cloneBody(view, bodyStart, s.to))
    effects.push(foldEffect.of({ headingFrom: s.from, from: bodyStart, to: s.to, animate: false }))
  }
  if (effects.length) view.dispatch({ effects, annotations: initialFoldAnnotation.of(true) })
}

/** Heading folding with the sidebar's Reveal motion; folded sections persist via `onFoldsChange`. */
export function markdownFolding(onFoldsChange: (keys: string[]) => void): Extension {
  const persist = EditorView.updateListener.of((u: ViewUpdate) => {
    const changed = u.transactions.some(
      (tr) =>
        !tr.annotation(initialFoldAnnotation) &&
        tr.effects.some((e) => e.is(foldEffect) || e.is(expandEffect) || e.is(dropEffect))
    )
    if (!changed) return
    const sections = sectionsOf(u.state.doc)
    const keys = u.state
      .field(foldField)
      .filter((e) => e.phase !== 'expanding')
      .map((e) => sections.find((s) => s.from === e.headingFrom)?.key)
      .filter((k): k is string => k !== undefined)
    onFoldsChange(keys)
  })
  return [foldField, foldGutterExt, persist]
}
