// @vitest-environment jsdom
import { afterEach, describe, expect, it } from 'vitest'
import { act, createElement } from 'react'
import { createRoot, type Root } from 'react-dom/client'
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

// A read-only portal (the at-rest page/markdown embed) must stay SELECTABLE: MarkdownPM renders selection
// natively (no drawSelection layer), so the content has to be a focusable contenteditable — editable stays
// true, edits are blocked by EditorState.readOnly alone. Flipping editable to false makes .cm-content
// contenteditable="false", which native selection can't drive → dead text selection. This pins that.
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
