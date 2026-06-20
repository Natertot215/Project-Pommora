// The CM6 adapter for decorations — the ONLY place behavior-layer intents become real CodeMirror
// decorations. A ViewPlugin recomputes on every doc/selection change: tokenize → active tokens →
// decorationsFor → CM6 mark (class) / replace (hide markers) / replace-widget (•, checkbox, HR).
// Inline-only replaces (no line-break crossing), so a ViewPlugin is valid; block-spanning chrome
// (blockquote/callout cards) moves to a StateField when it arrives.
import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate, WidgetType } from '@codemirror/view'
import type { Range } from '@codemirror/state'
import { chipCheckbox } from '../../design-system/tokens'
import { tokenize, activeTokenIndices } from '../tokens'
import { decorationsFor, type WidgetSpec } from '../decorations/intent'

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

class BulletWidget extends WidgetType {
  eq(): boolean {
    return true
  }
  toDOM(): HTMLElement {
    const el = document.createElement('span')
    el.className = 'md-li-marker md-bullet md-syntax'
    el.textContent = '•'
    return el
  }
}

/** An ordered-list marker (`1.`, `12.`…). Rendered literally — recoloured to the syntax label,
 *  occupying the same fixed marker zone as bullets/checkboxes so list text aligns across types. */
class OrderedWidget extends WidgetType {
  constructor(readonly label: string) {
    super()
  }
  eq(o: OrderedWidget): boolean {
    return o.label === this.label
  }
  toDOM(): HTMLElement {
    const el = document.createElement('span')
    el.className = 'md-li-marker md-ol-marker md-syntax'
    el.textContent = this.label
    return el
  }
}

/** Reuses the chip checkbox visual (`chipCheckbox`) + the nexus accent when checked; clicking it
 *  toggles the underlying `[ ]` ↔ `[x]` source (one transaction → native undo). */
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
    // Sit the box in the shared marker zone so checkbox lines align with bullet/ordered lines.
    const zone = document.createElement('span')
    zone.className = 'md-li-marker'
    const box = document.createElement('span')
    box.className = `${chipCheckbox} md-checkbox${this.checked ? ' md-checkbox-checked' : ''}`
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
    case 'ordered':
      return new OrderedWidget(spec.label)
    case 'checkbox':
      return new CheckboxWidget(spec.bracketFrom, spec.bracketTo, spec.checked)
  }
}

// One shared replace decoration for every hidden marker — they carry no per-instance data.
const hideMarker = Decoration.replace({})

function build(view: EditorView): DecorationSet {
  const text = view.state.doc.toString()
  const sel = view.state.selection.main
  const tokens = tokenize(text)
  const active = activeTokenIndices(tokens, sel.from, sel.to)
  const ranges: Range<Decoration>[] = []
  for (const it of decorationsFor(text, tokens, active, sel.head)) {
    if (it.kind === 'line') {
      // The list nesting level rides as a CSS var the line + its marker zone both read.
      ranges.push(
        Decoration.line({ class: it.className, attributes: { style: `--li-level:${it.level}` } }).range(it.from)
      )
      continue
    }
    if (it.to <= it.from) continue
    if (it.kind === 'class') ranges.push(Decoration.mark({ class: it.className }).range(it.from, it.to))
    else if (it.kind === 'hide') ranges.push(hideMarker.range(it.from, it.to))
    else ranges.push(Decoration.replace({ widget: widgetFor(it.spec) }).range(it.from, it.to))
  }
  return Decoration.set(ranges, true)
}

export const markdownDecorations = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet
    constructor(view: EditorView) {
      this.decorations = build(view)
    }
    update(u: ViewUpdate): void {
      if (u.docChanged || u.selectionSet || u.viewportChanged) this.decorations = build(u.view)
    }
  },
  { decorations: (v) => v.decorations }
)
