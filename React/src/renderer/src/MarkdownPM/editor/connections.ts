import { EditorView } from '@codemirror/view'
import { tokenize } from '../tokens'
import type { ConnectionsApi } from '../connections'

type GetApi = () => ConnectionsApi | undefined

function wikiLinkAt(view: EditorView, pos: number): { title: string } | null {
  const line = view.state.doc.lineAt(pos)
  const rel = pos - line.from
  const tk = tokenize(line.text).find((t) => t.kind === 'wikiLink' && rel >= t.range[0] && rel <= t.range[1])
  return tk ? { title: line.text.slice(tk.contentRange[0], tk.contentRange[1]) } : null
}

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
