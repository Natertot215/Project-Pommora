import type { HTMLAttributes, ReactNode } from 'react'
import { Glass } from '@samasante/liquid-glass'
import { useControlOptics } from './control-optics'

/**
 * GlassControls — Pommora's glass for **controls** (toolbars, segmented controls,
 * the autocomplete panel). Apple "Liquid Glass" via @samasante/liquid-glass: real
 * edge refraction over the live app, not a flat frost. The optical look comes from
 * the live control-optics store (tunable from the homepage slider panel); layout
 * (size / position / radius) is the consumer's job via style/className. Note: Glass
 * forces `display:inline-block` inline, so a flex consumer must re-assert
 * `display:flex` in its own inline style.
 */
export function GlassControls({
  children,
  style,
  ...rest
}: { children?: ReactNode } & HTMLAttributes<HTMLDivElement>): React.JSX.Element {
  const optics = useControlOptics()
  const r = style?.borderRadius
  return (
    <Glass optics={optics} radius={typeof r === 'number' ? r : undefined} style={style} {...rest}>
      {children}
    </Glass>
  )
}
