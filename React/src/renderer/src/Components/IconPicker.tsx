import './IconPicker.css'

interface Props {
  open: boolean
  onClose: () => void
}

/**
 * STUB — the real symbol-grid picker is designed in Figma. "Edit Icon" routes here so the wiring
 * is complete end-to-end; drop the designed UI in place of the placeholder body. The open/close
 * animation will later ride a shared dropdown primitive from the interactions layer (see Handoff).
 */
export function IconPicker({ open, onClose }: Props): React.JSX.Element | null {
  if (!open) return null
  return (
    <>
      <div className="icon-picker-scrim" onMouseDown={onClose} />
      <div className="icon-picker" role="dialog" aria-label="Edit icon">
        <span className="icon-picker-stub">Icon picker — coming from Figma</span>
      </div>
    </>
  )
}
