import type { ReactNode } from 'react'
import * as s from './interactionField.css'

/**
 * Interaction Field — the shared fill-quinary, rounded input surface for text + other inputs (the
 * ViewPane title, pane inputs…). One source so every input shares identical chrome. Render static
 * content for a display field; for editing, pass `fieldInputClass` to a raw <input> (e.g.
 * EditableInput) so the editor reuses the exact chrome with no focus ring/animation.
 */
export function InteractionField({
  children,
  className,
  onClick
}: {
  children: ReactNode
  className?: string
  onClick?: () => void
}): React.JSX.Element {
  return (
    <div className={className ? `${s.field} ${className}` : s.field} onClick={onClick}>
      {children}
    </div>
  )
}

/** The borderless, focus-ring-free input chrome — hand to EditableInput's `className`. */
export const fieldInputClass = s.input
