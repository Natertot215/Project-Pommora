import { useRef, useState, type CSSProperties } from 'react'
import { chipColorFor, colorLabel } from '@renderer/design-system/tokens/colorMap'
import { linkColorCss } from '@renderer/Detail/Views/Table/linkColor'
import type { ChipColorName } from '@renderer/design-system/tokens/chip.css'
import { Switch } from '@renderer/design-system/components/Switches/Switch'
import { Chip } from '../Chip'
import { ColorPicker } from './ColorPicker'
import * as s from './viewPane.css'

type LinkDisplay = 'link-url' | 'link-title'
export type LinkConfig = { link_underline?: boolean; link_display?: LinkDisplay; link_color?: string | undefined }

/** The link colour resolved for the pane: its chip key, display label, and the raw CSS colour that
 *  themes the pane (shared with the URL cell via linkColorCss). Absent = the system accent, "Default". */
function resolveLinkColor(color: string | undefined): { name: ChipColorName; label: string; css: string } {
  if (!color) return { name: 'accent', label: 'Default', css: linkColorCss(undefined) }
  const name = chipColorFor(color)
  return { name, label: colorLabel(name), css: linkColorCss(color) }
}

/**
 * The URL / Link property editor body — the def-level, per-property display config. Two toggles
 * (Underline, Full URL ⇄ page Title) plus a Colour chip that opens the recolor picker. The chosen
 * colour renders the link AND themes the pane's own Switches via a scoped `--accent`; absent = the
 * system accent, shown as "Default". The alias (a per-value Rename) overrides the Full URL / Title look
 * at render time — it's not configured here. The caller owns the single `property.setLinkConfig` write.
 */
export function URLEditor({
  underline,
  display,
  color,
  onSetConfig
}: {
  underline: boolean
  display: LinkDisplay
  color: string | undefined
  onSetConfig: (patch: LinkConfig) => void
}): React.JSX.Element {
  const [coloring, setColoring] = useState(false)
  const chipRef = useRef<HTMLButtonElement>(null)
  const link = resolveLinkColor(color)

  return (
    <div className={s.linkEditor} style={{ '--accent': link.css } as CSSProperties}>
      <div className={s.linkRow}>
        <span className={s.linkLabel}>Underline</span>
        <span className={s.switchScale}>
          <Switch checked={underline} onChange={(v) => onSetConfig({ link_underline: v })} ariaLabel="Underline links" />
        </span>
      </div>
      <div className={s.linkRow}>
        <span className={s.linkLabel}>Full URL</span>
        <span className={s.switchScale}>
          <Switch
            checked={display === 'link-url'}
            onChange={(v) => onSetConfig({ link_display: v ? 'link-url' : 'link-title' })}
            ariaLabel="Show the full URL"
          />
        </span>
      </div>
      <div className={s.linkRow}>
        <span className={s.linkLabel}>Color</span>
        <span className={s.linkColor}>
          <button ref={chipRef} type="button" className={s.linkChip} onClick={() => setColoring((v) => !v)}>
            <Chip shape="label" color={link.name} label={link.label} />
          </button>
          <ColorPicker
            open={coloring}
            selected={link.name}
            onPick={(next) => {
              onSetConfig({ link_color: next })
              setColoring(false)
            }}
            onDismiss={() => setColoring(false)}
            triggerRef={chipRef}
          />
        </span>
      </div>
    </div>
  )
}
