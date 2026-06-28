// The callout grip's right-click menu (grip-only, mirrors the table heading-row grip). A right-press in a
// callout's gutter strip pops a native Delete Callout menu; the generic editor menu stands down there because
// the rail hover flags the callout grip to main (see blockGripHover → setCalloutGrip). `blockAt` resolves the
// grip line to the whole callout box; delete removes those source lines plus one adjacent newline so no blank
// line is orphaned.
import { EditorView } from '@codemirror/view'
import { blockAt } from './blockModel'

export const calloutGripMenu = EditorView.domEventHandlers({
  contextmenu(e, view) {
    const line = (e.target as HTMLElement).closest?.('.cm-line.md-callout-first') as HTMLElement | null
    if (!line || e.clientX >= line.getBoundingClientRect().left) return false // not the grip gutter strip
    const block = blockAt(view.state.doc.toString(), view.posAtDOM(line))
    if (!block || block.kind !== 'callout') return false
    e.preventDefault()
    void window.nexus?.calloutMenu?.()?.then((action) => {
      if (action !== 'callout:delete') return
      const docLen = view.state.doc.length
      let from = block.from
      let to = block.to
      if (to < docLen) to += 1 // eat the trailing newline
      else if (from > 0) from -= 1 // last block in the doc: eat the preceding newline instead
      view.dispatch({ changes: { from, to, insert: '' }, userEvent: 'delete' })
      view.focus()
    })
    return true
  }
})
