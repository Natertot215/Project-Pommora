// The CM6 adapter for decorations — the ONLY place behavior-layer intents become real CodeMirror
// decorations. A ViewPlugin recomputes on every doc/selection change: tokenize → active tokens →
// decorationsFor → CM6 mark (class) / replace (hide markers) / replace-widget (HR). Inline-only for
// now (no line-break-crossing replaces), so a ViewPlugin is valid; block widgets move to a
// StateField when they arrive (Phase 3).
import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate, WidgetType } from '@codemirror/view'
import type { Range } from '@codemirror/state'
import { tokenize, activeTokenIndices } from '../tokens'
import { decorationsFor } from '../decorations/intent'

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

function build(view: EditorView): DecorationSet {
  const text = view.state.doc.toString()
  const sel = view.state.selection.main
  const tokens = tokenize(text)
  const active = activeTokenIndices(tokens, sel.from, sel.to)
  const ranges: Range<Decoration>[] = []
  for (const it of decorationsFor(text, tokens, active, sel.head)) {
    if (it.to <= it.from) continue
    if (it.kind === 'class') ranges.push(Decoration.mark({ class: it.className }).range(it.from, it.to))
    else if (it.kind === 'hide') ranges.push(Decoration.replace({}).range(it.from, it.to))
    else if (it.kind === 'widget') ranges.push(Decoration.replace({ widget: new HrWidget() }).range(it.from, it.to))
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
