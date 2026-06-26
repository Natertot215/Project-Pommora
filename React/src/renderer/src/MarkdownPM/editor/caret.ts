// A drawn caret, replacing the native browser one (which exposes only colour) with a CM `layer` we fully
// control: a rounded line-height bar and a smooth opacity fade instead of Chromium's hard blink. Native
// text SELECTION is left alone — we hide only the native caret (`caret-color: transparent` in Styles.css),
// so this is NOT drawSelection's all-or-nothing takeover. Shape + fade are pure CSS (`.mdpm-caret` /
// `@keyframes mdpm-blink`); this file is geometry only.
import { layer, RectangleMarker, type EditorView } from '@codemirror/view'
import { EditorSelection } from '@codemirror/state'

function caretMarkers(view: EditorView): RectangleMarker[] {
  const out: RectangleMarker[] = []
  for (const r of view.state.selection.ranges) {
    const cursor = r.empty ? r : EditorSelection.cursor(r.head, r.assoc)
    out.push(...RectangleMarker.forRange(view, 'mdpm-caret', cursor))
  }
  return out
}

export const customCaret = layer({
  above: true,
  class: 'mdpm-caretLayer',
  markers: caretMarkers,
  update(update, dom) {
    // Swap the keyframe name on any selection change so the fade restarts — the caret reads solid the
    // instant it moves, rather than mid-fade. Same trick CM's own cursor layer uses.
    if (update.transactions.some((tr) => tr.selection))
      dom.style.animationName = dom.style.animationName === 'mdpm-blink2' ? 'mdpm-blink' : 'mdpm-blink2'
    return update.docChanged || update.selectionSet
  }
})
