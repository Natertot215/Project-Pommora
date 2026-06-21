// The CM6 adapter — the only place behavior-layer intents become real CodeMirror decorations.
// A ViewPlugin works because replaces never cross a line break; block-spanning chrome would need a StateField.
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

/** The `•` shown in place of the source `-` when the caret is off the line. In-flow (replaces just
 *  the dash) so it occupies the dash's exact slot — moving the caret onto the line swaps it for the
 *  raw `- ` with no horizontal shift. */
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

/** Reuses the `chipCheckbox` visual + nexus accent when checked; clicking toggles the underlying
 *  `[ ]` ↔ `[x]` source in one transaction (native undo). */
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
