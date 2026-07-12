// @vitest-environment jsdom
import { afterEach, describe, expect, it } from 'vitest'
import { act, createElement } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { EditorView } from '@codemirror/view'
import { MarkdownEditor } from './index'

;(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true

let container: HTMLDivElement
let root: Root

afterEach(async () => {
  await act(async () => root.unmount())
  container.remove()
})

async function mount(readOnly: boolean): Promise<void> {
  container = document.createElement('div')
  document.body.appendChild(container)
  root = createRoot(container)
  await act(async () => {
    root.render(createElement(MarkdownEditor, { initialBody: 'hello world', onChange: () => {}, readOnly }))
  })
}

const view = (): EditorView => {
  const dom = container.querySelector('.cm-editor')
  const v = dom && EditorView.findFromDOM(dom as HTMLElement)
  if (!v) throw new Error('no EditorView')
  return v
}

// A read-only portal (the at-rest page/markdown embed) must stay SELECTABLE: MarkdownPM renders selection
// natively (no drawSelection layer), so the content has to be a focusable contenteditable — editable stays
// true. Flipping editable to false makes .cm-content contenteditable="false", which native selection can't
// drive → dead text selection. This pins that.
describe('read-only portal keeps its content selectable', () => {
  it('a read-only embed leaves .cm-content contenteditable', async () => {
    await mount(true)
    const content = container.querySelector('.cm-content')
    expect(content?.getAttribute('contenteditable')).toBe('true')
  })

  it('an editing embed is likewise contenteditable', async () => {
    await mount(false)
    const content = container.querySelector('.cm-content')
    expect(content?.getAttribute('contenteditable')).toBe('true')
  })
})

// EditorState.readOnly is ADVISORY — it doesn't block a programmatic view.dispatch({changes}) (formatKeymap,
// the drag/table/checkbox commands). With editable=true the DOM no longer blocks them either, so a
// changeFilter must drop doc changes while read-only, or Cmd+B would edit + autosave a read-only surface.
describe('read-only portal blocks programmatic edits', () => {
  it('drops a doc-changing dispatch while read-only', async () => {
    await mount(true)
    view().dispatch({ changes: { from: 0, insert: 'X' } })
    expect(view().state.doc.toString()).toBe('hello world')
  })

  it('allows the same dispatch once editing', async () => {
    await mount(false)
    view().dispatch({ changes: { from: 0, insert: 'X' } })
    expect(view().state.doc.toString()).toBe('Xhello world')
  })
})
