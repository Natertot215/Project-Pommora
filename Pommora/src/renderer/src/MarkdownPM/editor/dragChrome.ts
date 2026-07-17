// Shared drag chrome for both block-relocation gestures (list-item + whole-block): the in-place source shade
// and the fixed accent insertion line, defined once instead of per gesture.
import { StateEffect, StateField, type Line, type Range, type Text } from '@codemirror/state'
import { Decoration, type DecorationSet, EditorView } from '@codemirror/view'

// Walk the doc lines whose span intersects [from, to] inclusive (lineAt → next line at line.to + 1).
export function forEachLine(doc: Text, from: number, to: number, fn: (line: Line) => void): void {
  let line = doc.lineAt(from)
  while (line.from <= to) {
    fn(line)
    if (line.to + 1 > doc.length) break
    line = doc.lineAt(line.to + 1)
  }
}

// Ghost-shade: shades the dragged block's lines in place via a StateField (CM rebuilds line DOM on every
// change, so a raw class would be wiped — line decorations survive). One field, one effect, both gestures.
export const setShade = StateEffect.define<{ from: number; to: number } | null>()
const shadeLine = Decoration.line({ class: 'md-li-drag-source' })

export const shadeField = StateField.define<DecorationSet>({
  create: () => Decoration.none,
  update(deco, tr) {
    deco = deco.map(tr.changes)
    for (const e of tr.effects) {
      if (!e.is(setShade)) continue
      if (e.value === null) deco = Decoration.none
      else {
        const ranges: Range<Decoration>[] = []
        forEachLine(tr.state.doc, e.value.from, e.value.to, (line) =>
          ranges.push(shadeLine.range(line.from)),
        )
        deco = Decoration.set(ranges)
      }
    }
    return deco
  },
  provide: (f) => EditorView.decorations.from(f),
})

// Imperative accent insertion line over the editor — no floating ghost (the in-place shade shows what's
// moving). position:fixed → viewport coords, immune to the scroll-container ambiguity an absolute child of
// scrollDOM has. Created/torn-down by the gesture; no React tree.
export class Overlay {
  private line: HTMLElement | null = null

  show(left: number, top: number, width: number): void {
    if (!this.line) {
      const l = document.createElement('div')
      l.setAttribute('aria-hidden', 'true')
      l.style.cssText =
        'position:fixed;height:2px;border-radius:2px;background:var(--accent);pointer-events:none;z-index:1000'
      const dot = document.createElement('span')
      dot.style.cssText =
        'position:absolute;left:-3px;top:-2.5px;width:7px;height:7px;border-radius:50%;background:var(--accent)'
      l.appendChild(dot)
      document.body.appendChild(l)
      this.line = l
    }
    this.line.style.left = `${left}px`
    this.line.style.width = `${width}px`
    this.line.style.top = `${top}px`
  }

  hide(): void {
    this.line?.remove()
    this.line = null
  }
}
