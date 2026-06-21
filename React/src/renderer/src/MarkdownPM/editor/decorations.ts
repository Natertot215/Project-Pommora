// A ViewPlugin is valid because replaces never cross a line break (block-spanning chrome would need a StateField).
import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate, WidgetType } from '@codemirror/view'
import type { Extension, Range } from '@codemirror/state'
import { chipCheckbox } from '../../design-system/tokens'
import { tokenize, activeTokenIndices } from '../tokens'
import { decorationsFor, type WidgetSpec } from '../decorations/intent'
import type { ConnectionsApi } from '../connections'

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
    el.className = 'md-bullet'
    el.textContent = '•'
    return el
  }
}

class CheckboxWidget extends WidgetType {
  constructor(
    readonly bracketFrom: number,
    readonly bracketTo: number,
    readonly checked: boolean
  ) {
    super()
  }
  eq(o: CheckboxWidget): boolean {
    return o.checked === this.checked && o.bracketFrom === this.bracketFrom
  }
  toDOM(view: EditorView): HTMLElement {
    const zone = document.createElement('span')
    zone.className = 'md-li-marker'
    const box = document.createElement('span')
    box.className = `${chipCheckbox} md-checkbox${this.checked ? ' md-checkbox-checked' : ''}`
    if (this.checked) {
      box.innerHTML =
        '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>'
    }
    box.addEventListener('mousedown', (e) => {
      e.preventDefault()
      view.dispatch({ changes: { from: this.bracketFrom, to: this.bracketTo, insert: this.checked ? '[ ]' : '[x]' } })
    })
    zone.appendChild(box)
    return zone
  }
  ignoreEvent(): boolean {
    return false
  }
}

function widgetFor(spec: WidgetSpec): WidgetType {
  switch (spec.type) {
    case 'hr':
      return new HrWidget()
    case 'bullet':
      return new BulletWidget()
    case 'checkbox':
      return new CheckboxWidget(spec.bracketFrom, spec.bracketTo, spec.checked)
  }
}

const hideMarker = Decoration.replace({})
const NO_ACTIVE = new Set<number>()

function build(view: EditorView, conn: ConnectionsApi | undefined): DecorationSet {
  const text = view.state.doc.toString()
  const focused = view.hasFocus
  const sel = view.state.selection.main
  const tokens = tokenize(text)
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
    if (it.to <= it.from) continue
    if (it.kind === 'class') ranges.push(Decoration.mark({ class: it.className }).range(it.from, it.to))
    else if (it.kind === 'hide') ranges.push(hideMarker.range(it.from, it.to))
    else ranges.push(Decoration.replace({ widget: widgetFor(it.spec) }).range(it.from, it.to))
  }
  if (conn) {
    tokens.forEach((tk, i) => {
      if (tk.kind !== 'wikiLink') return
      const status = conn.resolve(text.slice(tk.contentRange[0], tk.contentRange[1])).status
      if (status === 'phantom') return // unresolved → raw `[[Foo]]`, brackets visible + inert (spec)
      ranges.push(Decoration.mark({ class: `md-connection-${status}` }).range(tk.contentRange[0], tk.contentRange[1]))
      const bracket = active.has(i) ? Decoration.mark({ class: 'md-bracket' }) : hideMarker
      for (const [s, e] of tk.markerRanges) ranges.push(bracket.range(s, e))
    })
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
        // Decorations cover the whole doc, so only doc/selection/focus changes matter — not scroll.
        if (u.docChanged || u.selectionSet || u.focusChanged) this.decorations = build(u.view, getConn())
      }
    },
    { decorations: (v) => v.decorations }
  )
}
