import type { CSSProperties, HTMLAttributes, ReactNode } from 'react'
import { shadowStandardVar } from '../tokens/color.css'

/**
 * GlassPane — Pommora's native CSS frost for panes/dropdowns (the menu MenuSurface + the toolbar
 * Navigation/Settings panels). Same recipe as the static frostMaterial (glass-material.ts) — a dimmed
 * blur with a glassy edge — with its own pane-tuned params (PANE_FROST); the drop shadow is the shared
 * --shadow-standard token.
 */
export interface FrostParams {
  /** backdrop blur radius, px. */
  blur: number
  /** backdrop brightness, % (100 = neutral). */
  brightness: number
  /** backdrop saturate, % (100 = neutral). */
  saturate: number
  /** white border opacity, 0..1. */
  borderAlpha: number
  /** top specular edge highlight opacity, 0..1. */
  topSpecular: number
  /** hairline inner-ring opacity, 0..1. */
  innerRing: number
  /** bottom-rim light pooling opacity, 0..1. */
  lowerRim: number
  /** bottom-rim reach, px — how far the pooling rises from the lower edge (offset + negative spread). */
  depth: number
  /** bottom-rim blur, px. */
  rimBlur: number
}

export const PANE_FROST: FrostParams = {
  blur: 6,
  brightness: 90,
  saturate: 100,
  borderAlpha: 0.12,
  topSpecular: 0.35,
  innerRing: 0.08,
  lowerRim: 0.08,
  depth: 12,
  rimBlur: 18
}

/** 0..1 → 2-digit hex alpha (colors authored as hex per the project rule). */
const hexA = (n: number): string =>
  Math.round(Math.max(0, Math.min(1, n)) * 255)
    .toString(16)
    .padStart(2, '0')
    .toUpperCase()

export function frostStyle(p: FrostParams): CSSProperties {
  const filter = `blur(${p.blur}px) brightness(${p.brightness}%)${p.saturate !== 100 ? ` saturate(${p.saturate}%)` : ''}`
  return {
    background: 'transparent',
    backdropFilter: filter,
    WebkitBackdropFilter: filter,
    border: `1px solid #FFFFFF${hexA(p.borderAlpha)}`,
    boxShadow: [
      `inset 0 1px 0 #FFFFFF${hexA(p.topSpecular)}`,
      `inset 0 0 0 1px #FFFFFF${hexA(p.innerRing)}`,
      `inset 0 -${p.depth}px ${p.rimBlur}px -${p.depth}px #FFFFFF${hexA(p.lowerRim)}`,
      shadowStandardVar
    ].join(', ')
  }
}

export function GlassPane({
  children,
  style,
  ...rest
}: { children?: ReactNode } & HTMLAttributes<HTMLDivElement>): React.JSX.Element {
  return (
    <div style={{ ...frostStyle(PANE_FROST), ...style }} {...rest}>
      {children}
    </div>
  )
}
