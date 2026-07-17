// A ViewPlugin is valid because replaces never cross a line break (block-spanning chrome would need a StateField).
import {
  Decoration,
  type DecorationSet,
  EditorView,
  ViewPlugin,
  type ViewUpdate,
  WidgetType,
} from '@codemirror/view'
import type { Extension, Range } from '@codemirror/state'
import { chipBoxGeometry } from '../../design-system/tokens'
import { tokenize, activeTokenIndices, type Token } from '../tokens'
import { docString } from './docCache'
import {
  decorationsFor,
  fencedCodeRanges,
  GLYPH_CLASS,
  type WidgetSpec,
} from '../decorations/intent'
import type { ConnectionsApi } from '../connections'
import { isValidLink } from '@shared/links'

class HrWidget extends WidgetType {
  eq(): boolean {
    return true
  }
  toDOM(): HTMLElement {
    const el = document.createElement('span')
    el.className = 'md-hr'
    return el
  }
}

// In-flow (replaces just the dash) so it sits in the dash's exact slot — no shift when the caret reveals the raw `- `.
class BulletWidget extends WidgetType {
  eq(): boolean {
    return true
  }
  toDOM(): HTMLElement {
    const el = document.createElement('span')
    el.className = `md-bullet ${GLYPH_CLASS}`
    el.textContent = '•'
    return el
  }
  // WidgetType.ignoreEvent defaults to true — CM would swallow every event from this DOM, so the listDrag
  // pointerdown never fires on a bullet glyph. The checkbox widget overrides it for the same reason.
  ignoreEvent(): boolean {
    return false
  }
}

class CheckboxWidget extends WidgetType {
  constructor(
    readonly bracketFrom: number,
    readonly checked: boolean,
  ) {
    super()
  }
  eq(o: CheckboxWidget): boolean {
    return o.checked === this.checked && o.bracketFrom === this.bracketFrom
  }
  toDOM(): HTMLElement {
    // Toggle-on-click + drag-on-hold are both owned by the listDrag extension via the shared glyph class —
    // this widget only renders. Keeping the press handler here would flip the box on a press-to-drag.
    const zone = document.createElement('span')
    zone.className = `md-li-marker ${GLYPH_CLASS}`
    const box = document.createElement('span')
    box.className = `${chipBoxGeometry} md-checkbox${this.checked ? ' md-checkbox-checked' : ''}`
    if (this.checked) {
      box.innerHTML =
        '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>'
    }
    zone.appendChild(box)
    return zone
  }
  ignoreEvent(): boolean {
    return false
  }
}

// A non-replacing element pinned at a line's start (side -1) — e.g. the nested-quote bar, which must be a real
// element to sit OVER the fill with its own rounded caps. Positioned + shaped entirely in CSS by its class.
class LineWidget extends WidgetType {
  constructor(readonly className: string) {
    super()
  }
  eq(o: LineWidget): boolean {
    return o.className === this.className
  }
  toDOM(): HTMLElement {
    const el = document.createElement('span')
    el.className = this.className
    el.setAttribute('aria-hidden', 'true')
    return el
  }
}

// One outliner rail: an ancestor-level vertical guide, pinned at the line start (side -1) and positioned +
// shaped entirely in CSS from --rail-level (its ancestor column) plus the type class (glyph-centre offset).
// first/last carry the run-end caps, so a rail only rounds where its run actually begins/ends.
class OutlinerRailWidget extends WidgetType {
  constructor(
    readonly level: number,
    readonly typeClass: string,
    readonly first: boolean,
    readonly last: boolean,
  ) {
    super()
  }
  eq(o: OutlinerRailWidget): boolean {
    return (
      o.level === this.level &&
      o.typeClass === this.typeClass &&
      o.first === this.first &&
      o.last === this.last
    )
  }
  toDOM(): HTMLElement {
    const el = document.createElement('span')
    el.className = `md-outliner-rail ${this.typeClass}${this.first ? ' md-outliner-first' : ''}${this.last ? ' md-outliner-last' : ''}`
    el.style.setProperty('--rail-level', String(this.level))
    el.setAttribute('aria-hidden', 'true')
    return el
  }
}

function widgetFor(spec: WidgetSpec): WidgetType {
  switch (spec.type) {
    case 'hr':
      return new HrWidget()
    case 'bullet':
      return new BulletWidget()
    case 'checkbox':
      return new CheckboxWidget(spec.bracketFrom, spec.checked)
  }
}

const hideMarker = Decoration.replace({})
const NO_ACTIVE = new Set<number>()

// Tokenize only the on-screen lines, not the whole document — the heavy mdast parse + global-regex
// passes per keystroke/caret-move are what made long docs lag and the caret jitter. Tokens are shifted
// back to absolute offsets, and any landing inside a fence opened above the viewport are dropped (a
// viewport-only tokenize can't see that fence). Paired with a rebuild on `viewportChanged` (scroll).
function visibleInlineTokens(view: EditorView, text: string): Token[] {
  const doc = view.state.doc
  const spans: [number, number][] = []
  for (const { from, to } of view.visibleRanges) {
    const a = doc.lineAt(from).from
    const b = doc.lineAt(to).to
    const prev = spans[spans.length - 1]
    if (prev && a <= prev[1] + 1) prev[1] = Math.max(prev[1], b)
    else spans.push([a, b])
  }
  const fences = fencedCodeRanges(text)
  const insideFence = (p: number): boolean => fences.some(([fa, fb]) => p >= fa && p < fb)
  const out: Token[] = []
  for (const [a, b] of spans) {
    for (const tk of tokenize(text.slice(a, b))) {
      const start = tk.range[0] + a
      if (insideFence(start)) continue
      out.push({
        kind: tk.kind,
        range: [start, tk.range[1] + a],
        contentRange: [tk.contentRange[0] + a, tk.contentRange[1] + a],
        markerRanges: tk.markerRanges.map(([s, e]) => [s + a, e + a] as [number, number]),
      })
    }
  }
  return out
}

function build(view: EditorView, conn: ConnectionsApi | undefined): DecorationSet {
  const text = docString(view.state.doc)
  const focused = view.hasFocus
  const sel = view.state.selection.main
  const tokens = visibleInlineTokens(view, text)
  const active = focused ? activeTokenIndices(tokens, sel.from, sel.to) : NO_ACTIVE
  const head = focused ? sel.head : -1
  const ranges: Range<Decoration>[] = []
  for (const it of decorationsFor(text, tokens, active, head)) {
    if (it.kind === 'line') {
      const spec =
        it.level === undefined
          ? { class: it.className }
          : { class: it.className, attributes: { style: `--li-level:${it.level}` } }
      ranges.push(Decoration.line(spec).range(it.from))
      continue
    }
    if (it.kind === 'lineWidget') {
      ranges.push(
        Decoration.widget({ widget: new LineWidget(it.className), side: -1 }).range(it.from),
      )
      continue
    }
    if (it.kind === 'rail') {
      ranges.push(
        Decoration.widget({
          widget: new OutlinerRailWidget(it.level, it.typeClass, it.first, it.last),
          side: -1,
        }).range(it.from),
      )
      continue
    }
    if (it.to <= it.from) continue
    if (it.kind === 'class')
      ranges.push(Decoration.mark({ class: it.className }).range(it.from, it.to))
    else if (it.kind === 'hide') ranges.push(hideMarker.range(it.from, it.to))
    else ranges.push(Decoration.replace({ widget: widgetFor(it.spec) }).range(it.from, it.to))
  }
  // External links by static URL validity. Title: valid → md-link, invalid → md-link-invalid (dimmed).
  // Brackets `[ ]`: always shown dimmed for invalid (the broken-link tell), hidden-until-caret for valid.
  // The `(url)` stays hidden at rest either way; on caret it reveals (valid → italic+underline, invalid → dimmed).
  tokens.forEach((tk, i) => {
    if (tk.kind !== 'link') return
    const [open, close] = tk.markerRanges // `[`  and  `](url)`
    const bracketEnd = close[0] + 1 // the `]`
    const valid = isValidLink(text.slice(bracketEnd + 1, close[1] - 1)) // strip `](` head + `)` tail
    const isActive = active.has(i)
    ranges.push(
      Decoration.mark({ class: valid ? 'md-link' : 'md-link-invalid' }).range(
        tk.contentRange[0],
        tk.contentRange[1],
      ),
    )
    const dim = Decoration.mark({ class: 'md-control' })
    if (!valid || isActive) {
      ranges.push(dim.range(open[0], open[1])) // [
      ranges.push(dim.range(close[0], bracketEnd)) // ]
    } else {
      ranges.push(hideMarker.range(open[0], open[1]))
      ranges.push(hideMarker.range(close[0], bracketEnd))
    }
    if (isActive)
      ranges.push(
        Decoration.mark({ class: valid ? 'md-link-url' : 'md-control' }).range(
          bracketEnd,
          close[1],
        ),
      ) // (url)
    else ranges.push(hideMarker.range(bracketEnd, close[1]))
  })
  if (conn) {
    tokens.forEach((tk, i) => {
      if (tk.kind !== 'wikiLink') return
      const status = conn.resolve(text.slice(tk.contentRange[0], tk.contentRange[1])).status
      if (status === 'phantom') return // unresolved → raw `[[Foo]]`, brackets visible + inert (spec)
      ranges.push(
        Decoration.mark({ class: `md-connection-${status}` }).range(
          tk.contentRange[0],
          tk.contentRange[1],
        ),
      )
      const bracket = active.has(i) ? Decoration.mark({ class: 'md-bracket' }) : hideMarker
      for (const [s, e] of tk.markerRanges) ranges.push(bracket.range(s, e))
    })
  }
  const bidirRe = /↔/g
  for (const { from, to } of view.visibleRanges) {
    const seg = text.slice(from, to)
    let m: RegExpExecArray | null
    while ((m = bidirRe.exec(seg)) !== null) {
      const p = from + m.index
      ranges.push(Decoration.mark({ class: 'md-sym-bidir' }).range(p, p + 1))
    }
  }
  return Decoration.set(ranges, true)
}

export function markdownDecorations(getConn: () => ConnectionsApi | undefined): Extension {
  return ViewPlugin.fromClass(
    class {
      decorations: DecorationSet
      constructor(view: EditorView) {
        this.decorations = build(view, getConn())
      }
      update(u: ViewUpdate): void {
        // Inline tokens are viewport-scoped, so scroll (viewportChanged) must rebuild too — newly
        // revealed lines need their decorations. Line-level chrome still spans the whole doc.
        if (u.docChanged || u.selectionSet || u.focusChanged || u.viewportChanged)
          this.decorations = build(u.view, getConn())
      }
    },
    { decorations: (v) => v.decorations },
  )
}
