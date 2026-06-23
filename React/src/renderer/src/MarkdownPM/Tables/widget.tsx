import { Decoration, type DecorationSet, EditorView, WidgetType } from '@codemirror/view'
import { StateField, type EditorState, type Extension, type Range } from '@codemirror/state'
import { createRoot, type Root } from 'react-dom/client'
import { tableRegions } from './regions'
import { parseTable } from './codec'
import type { TableModel } from './model'
import { TableView } from './TableView'

// The table source stays in the document (canonical GFM); this block-replace renders an interactive
// HTML widget OVER it. `text` is the widget's identity — an unchanged table reuses its DOM, no remount.
class TableWidget extends WidgetType {
  private root: Root | undefined

  constructor(
    readonly text: string,
    readonly model: TableModel
  ) {
    super()
  }

  eq(other: TableWidget): boolean {
    return other.text === this.text
  }

  toDOM(): HTMLElement {
    const dom = document.createElement('div')
    dom.className = 'mdpm-tbl-widget'
    this.root = createRoot(dom)
    this.root.render(<TableView model={this.model} />)
    return dom
  }

  destroy(): void {
    // React forbids unmounting synchronously inside a render/commit; CM may destroy mid-update.
    const root = this.root
    this.root = undefined
    if (root) queueMicrotask(() => root.unmount())
  }

  ignoreEvent(): boolean {
    return true
  }
}

export function buildWidgetDecorations(state: EditorState): DecorationSet {
  const doc = state.doc
  const ranges: Range<Decoration>[] = []
  for (const region of tableRegions(doc.toString())) {
    const text = doc.sliceString(region.from, region.to)
    const model = parseTable(text)
    if (!model) continue
    ranges.push(
      Decoration.replace({ widget: new TableWidget(text, model), block: true }).range(region.from, region.to)
    )
  }
  return Decoration.set(ranges, true)
}

const widgetField = StateField.define<DecorationSet>({
  create: buildWidgetDecorations,
  update: (deco, tr) => (tr.docChanged ? buildWidgetDecorations(tr.state) : deco),
  provide: (f) => EditorView.decorations.from(f)
})

export function tableWidgetExtension(): Extension {
  return widgetField
}
