// Screen-reader plumbing for the drag engine. One shared, visually-hidden ARIA live region announces
// keyboard-drag progress; one shared hidden instructions element is referenced by every draggable's
// aria-describedby. Singletons appended to <body> (Chromium/Electron — no SSR), created lazily.

export const INSTRUCTIONS_ID = 'dnd-instructions'

const HIDDEN: Partial<CSSStyleDeclaration> = {
  position: 'fixed',
  top: '0',
  left: '0',
  width: '1px',
  height: '1px',
  margin: '-1px',
  padding: '0',
  overflow: 'hidden',
  clipPath: 'inset(100%)',
  whiteSpace: 'nowrap',
  border: '0'
}

let region: HTMLElement | null = null
let instructions: HTMLElement | null = null

/** Announce a drag-progress message to assistive tech (assertive live region). */
export function announce(message: string): void {
  if (typeof document === 'undefined') return
  if (!region) {
    region = document.createElement('div')
    region.setAttribute('role', 'status')
    region.setAttribute('aria-live', 'assertive')
    region.setAttribute('aria-atomic', 'true')
    Object.assign(region.style, HIDDEN)
    document.body.appendChild(region)
  }
  region.textContent = message
}

/** Ensure the hidden keyboard-instructions element exists (target of every draggable's describedby). */
export function ensureInstructions(): void {
  if (typeof document === 'undefined' || instructions) return
  instructions = document.createElement('div')
  instructions.id = INSTRUCTIONS_ID
  Object.assign(instructions.style, HIDDEN)
  instructions.textContent =
    'To pick up a draggable item, press space or enter. While dragging, use the arrow keys to move the item. Press space or enter again to drop it, or press escape to cancel.'
  document.body.appendChild(instructions)
}
