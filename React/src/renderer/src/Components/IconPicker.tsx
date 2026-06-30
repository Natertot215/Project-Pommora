import { createPortal } from 'react-dom'
import { GlassPane } from '@renderer/design-system/materials'
import { dropdownMenu, dropdownMenuClosing } from '@renderer/design-system/animations.css'
import { useExitPresence } from '@renderer/design-system/useExitPresence'
import { cx } from '@renderer/design-system/cx'
import './IconPicker.css'

interface Props {
  open: boolean
  onClose: () => void
}

/**
 * STUB — the real symbol-grid picker is designed in Figma. "Edit Icon" routes here so the wiring is
 * complete end-to-end; drop the designed UI in place of the placeholder body. Chrome is shared: a
 * frosted GlassPane that blooms open + retracts closed (the `dropdown-menu` motion), centered over a
 * dismiss scrim.
 */
export function IconPicker({ open, onClose }: Props): React.JSX.Element | null {
  const { mounted, closing } = useExitPresence(open)
  if (!mounted) return null
  // Portaled to body so the fixed scrim escapes any clipped/transformed ancestor (e.g. the PaneSlider).
  return createPortal(
    <div className="icon-picker-scrim" onMouseDown={onClose}>
      <GlassPane
        className={cx('icon-picker', closing ? dropdownMenuClosing : dropdownMenu)}
        role="dialog"
        aria-label="Edit icon"
        onMouseDown={(e) => e.stopPropagation()}
        style={{ '--dropdown-origin': 'center' } as React.CSSProperties}
      >
        <span className="icon-picker-stub">Icon picker — coming from Figma</span>
      </GlassPane>
    </div>,
    document.body
  )
}
