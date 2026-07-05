import { Fragment } from 'react'
import { GlassControls } from '../../materials'
import { Icon, type IconName } from '../../symbols'
import { vars, text, type ButtonSize, type IconSize } from '../../tokens'
import * as s from './segmented.css'

/** One segment of a segmented control. `active` is accepted but never drawn (no
 *  active-state fill, per spec) — it only surfaces as `aria-pressed` for toggles. */
export type Segment = {
  icon: IconName
  label?: string
  onClick?: () => void
  disabled?: boolean
  active?: boolean
  /** Tooltip + accessible name. */
  title?: string
}

type SegmentedProps = {
  segments: Segment[]
  size?: ButtonSize
  /** Override the size bundle's horizontal segment padding (e.g. a tighter Back/Forward). */
  paddingX?: string
  /** Override the glyph size only (geometry unchanged) — e.g. larger Back/Forward chevrons. */
  iconSize?: IconSize
  className?: string
  /** Drop the glass pill, rendering bare buttons (the consumer supplies its own glass layer). */
  glass?: boolean
}

function Segmented({
  segments,
  size = 'button-large',
  paddingX,
  iconSize,
  withLabel,
  className,
  glass = true
}: SegmentedProps & { withLabel: boolean }): React.JSX.Element {
  const g = vars.size.control[size]
  const containerClass = className ? `${s.container} ${className}` : s.container
  const containerStyle = { height: g.height, borderRadius: g.radius, display: 'flex', alignItems: 'center' }
  const buttons = (
    <>
      {segments.map((seg, i) => (
        <Fragment key={`${i}-${seg.icon}`}>
          {i > 0 && (
            <span className={s.divider} style={{ height: g.dividerHeight }} />
          )}
          <button
            type="button"
            className={s.segment}
            style={{
              height: g.segmentHeight,
              borderRadius: g.segmentRadius,
              paddingInline: paddingX ?? g.paddingX,
              fontSize: iconSize ? vars.size.icon[iconSize] : g.icon
            }}
            onClick={seg.onClick}
            disabled={seg.disabled}
            title={seg.title}
            aria-label={seg.title ?? seg.label}
            aria-pressed={seg.active}
          >
            <Icon name={seg.icon} />
            {withLabel && seg.label && <span className={text.control.standard}>{seg.label}</span>}
          </button>
        </Fragment>
      ))}
    </>
  )
  return glass ? (
    <GlassControls className={containerClass} style={containerStyle}>
      {buttons}
    </GlassControls>
  ) : (
    <div className={containerClass} style={containerStyle}>
      {buttons}
    </div>
  )
}

/** Icon-only segmented control (Figma SEGMENTED · SYMBOL). The toolbar uses this. */
export function SegmentedSymbol(props: SegmentedProps): React.JSX.Element {
  return <Segmented {...props} withLabel={false} />
}

/** Icon + label segmented control (Figma SEGMENTED · BUTTON), same core. */
export function SegmentedButton(props: SegmentedProps): React.JSX.Element {
  return <Segmented {...props} withLabel />
}
