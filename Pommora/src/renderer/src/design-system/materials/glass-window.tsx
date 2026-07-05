import type { HTMLAttributes, ReactNode } from 'react'
import { frostMaterial } from './glass-material'

/**
 * GlassWindow — Pommora's glass for the **window** tier: the app's largest,
 * backmost glass — the window frame the sidebar attaches to. Spreads the shared
 * CSS frost material; its own component so window glass can diverge from
 * surface/control glass later (override props after the spread). Layout (size /
 * position / radius) is the consumer's job via style/className.
 */
export function GlassWindow({
  children,
  style,
  ...rest
}: { children?: ReactNode } & HTMLAttributes<HTMLDivElement>): React.JSX.Element {
  return (
    <div style={{ ...frostMaterial, ...style }} {...rest}>
      {children}
    </div>
  )
}
