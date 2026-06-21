// CM6 glue for connections: click a resolved [[Title]] to navigate, and per-status styling so
// resolved / phantom / ambiguous links read differently. Resolution comes from the host via a
// getter (kept current as the nexus tree changes), not captured at mount.
import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate } from '@codemirror/view'
import type { Range } from '@codemirror/state'
import { tokenize } from '../tokens'
import type { ConnectionsApi } from '../connections'

type GetApi = () => ConnectionsApi | undefined

/** A wikiLink token at a document position (clicked or hovered), with its raw title. */
function wikiLinkAt(view: EditorView, pos: number): { title: string } | null {
  const line = view.state.doc.lineAt(pos)
  const rel = pos - line.from
  const tk = tokenize(line.text).find((t) => t.kind === 'wikiLink' && rel >= t.range[0] && rel <= t.range[1])
  return tk ? { title: line.text.slice(tk.contentRange[0], tk.contentRange[1]) } : null
}

/** Click a resolved connection → open its page. Phantom/ambiguous links don't navigate. */
export function connectionClicks(getApi: GetApi): ReturnType<typeof EditorView.domEventHandlers> {
  return EditorView.domEventHandlers({
    mousedown(event, view) {
      if (event.button !== 0) return false
      const api = getApi()
      if (!api) return false
      const pos = view.posAtCoords({ x: event.clientX, y: event.clientY })
      if (pos == null) return false
      const hit = wikiLinkAt(view, pos)
      if (!hit) return false
      const res = api.resolve(hit.title)
      if (res.status !== 'resolved' || !res.page) return false
      event.preventDefault()
      api.open(res.page)
      return true
    }
  })
}

/** Per-status mark over each connection's content: md-connection plus a status modifier. */
export function connectionStatus(getApi: GetApi): ReturnType<typeof ViewPlugin.fromClass> {
  const build = (view: EditorView): DecorationSet => {
    const api = getApi()
    if (!api) return Decoration.none
    const text = view.state.doc.toString()
    const ranges: Range<Decoration>[] = []
    for (const tk of tokenize(text)) {
      if (tk.kind !== 'wikiLink') continue
      const status = api.resolve(text.slice(tk.contentRange[0], tk.contentRange[1])).status
      ranges.push(Decoration.mark({ class: `md-connection-${status}` }).range(tk.contentRange[0], tk.contentRange[1]))
    }
    return Decoration.set(ranges, true)
  }
  return ViewPlugin.fromClass(
    class {
      decorations: DecorationSet
      constructor(view: EditorView) {
        this.decorations = build(view)
      }
      update(u: ViewUpdate): void {
        if (u.docChanged || u.viewportChanged) this.decorations = build(u.view)
      }
    },
    { decorations: (v) => v.decorations }
  )
}
