import { EditorView } from '@codemirror/view'
import { tokenize } from '../tokens'
import type { ConnectionsApi, ConnPage } from '../connections'

type GetApi = () => ConnectionsApi | undefined

/** KNOB — B-7's hover-intent delay: how long the pointer rests on a connection before the card. */
const CONN_HOVER_INTENT_MS = 450

function wikiLinkAt(view: EditorView, pos: number): { title: string } | null {
  const line = view.state.doc.lineAt(pos)
  const rel = pos - line.from
  const tk = tokenize(line.text).find(
    (t) => t.kind === 'wikiLink' && rel >= t.range[0] && rel <= t.range[1],
  )
  return tk ? { title: line.text.slice(tk.contentRange[0], tk.contentRange[1]) } : null
}

/** The resolved connection page under the pointer, or null — the shared hit-test for every handler. */
function resolvedPageAt(view: EditorView, api: ConnectionsApi, event: MouseEvent): ConnPage | null {
  const pos = view.posAtCoords({ x: event.clientX, y: event.clientY })
  if (pos == null) return null
  const hit = wikiLinkAt(view, pos)
  if (!hit) return null
  const res = api.resolve(hit.title)
  return res.status === 'resolved' && res.page ? res.page : null
}

export function connectionClicks(getApi: GetApi): ReturnType<typeof EditorView.domEventHandlers> {
  // The pending hover intent (B-7) — armed on mouseover of a resolved connection, cancelled the
  // moment the pointer leaves it (mouseout fires per CM6 text span; re-entry re-arms fresh).
  let hoverTimer: ReturnType<typeof setTimeout> | null = null
  const cancelHover = (): void => {
    if (hoverTimer) {
      clearTimeout(hoverTimer)
      hoverTimer = null
    }
  }
  return EditorView.domEventHandlers({
    mouseover(event, view) {
      const api = getApi()
      if (!api?.hover) return false
      cancelHover()
      // Cheap class gate FIRST (the every-mouseover hard rule): only a resolved connection's
      // decoration span warrants the layout read + line tokenize below.
      const el = (event.target as HTMLElement).closest?.('.md-connection-resolved')
      if (!el) return false
      const page = resolvedPageAt(view, api, event)
      if (!page) return false
      hoverTimer = setTimeout(
        () => api.hover?.(page, el.getBoundingClientRect()),
        CONN_HOVER_INTENT_MS,
      )
      return false
    },
    mouseout() {
      cancelHover()
      return false
    },
    // Navigate on a plain single-click (spec). Handled on `click`, not `mousedown`, and skipped when the
    // selection is non-empty — so dragging across a connection highlights it instead of navigating away.
    click(event, view) {
      if (event.button !== 0 || event.detail !== 1 || !view.state.selection.main.empty) return false
      const api = getApi()
      if (!api) return false
      const page = resolvedPageAt(view, api, event)
      if (!page) return false
      event.preventDefault()
      // The one modifier branch (H-11/I-19): ⌘ takes the host's other route when it offers one.
      if (event.metaKey && api.bypass) api.bypass(page)
      else api.open(page)
      return true
    },
    // Right-click on a resolved connection hands off to the host's menu hook (Open in Preview et al).
    contextmenu(event, view) {
      const api = getApi()
      if (!api?.menu) return false
      const page = resolvedPageAt(view, api, event)
      if (!page) return false
      event.preventDefault()
      api.menu(page)
      return true
    },
  })
}
