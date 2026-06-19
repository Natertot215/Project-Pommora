import { createGlobalTheme, style } from '@vanilla-extract/css'

/**
 * Typography primitives — the raw type scale and the single source of truth.
 * Edit a value here and it propagates to every composed text style and every
 * component that uses one. Mirrors the Figma "Pommora - React" text styles
 * (Inter, letter-spacing 0). Full spec: .claude/Features/Typography.md.
 */
export const font = createGlobalTheme(':root', {
  family:
    "'Inter Variable', -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif",
  // The four Inter weights, named on a standard → bold ladder. Single source —
  // edit a number here (or add a step) and it flows to every text style and the
  // --weight-* CSS vars. Inter is variable (axis 100–900), so any value renders.
  weight: {
    standard: '400',
    emphasized: '500',
    semibold: '600',
    bold: '700'
  },
  // Size + line height, co-located per style (px), matching the Figma ramp.
  scale: {
    largeTitle: { size: '26px', line: '32px' },
    title1: { size: '22px', line: '26px' },
    title2: { size: '17px', line: '22px' },
    title3: { size: '15px', line: '20px' },
    headline: { size: '13px', line: '16px' },
    body: { size: '13px', line: '16px' },
    callout: { size: '12px', line: '15px' },
    control: { size: '12px', line: '15px' },
    caption: { size: '11px', line: '14px' },
    footnote: { size: '10px', line: '13px' }
  }
})

type ScaleKey = keyof typeof font.scale
type WeightKey = keyof typeof font.weight

// Compose one ramp style into its two variant classes — `.standard` + `.emphasized`.
// NB: those variant-slot names are a separate layer from the weight names above;
// a slot maps to whatever weight its role calls for (e.g. Headline's `.standard`
// slot resolves to the `emphasized` 500 weight). Params name the weight per slot.
const ramp = (
  key: ScaleKey,
  standardWeight: WeightKey,
  emphasizedWeight: WeightKey
): { standard: string; emphasized: string } => {
  const base = {
    fontFamily: font.family,
    fontSize: font.scale[key].size,
    lineHeight: font.scale[key].line,
    letterSpacing: 0
  }
  return {
    standard: style({ ...base, fontWeight: font.weight[standardWeight] }),
    emphasized: style({ ...base, fontWeight: font.weight[emphasizedWeight] })
  }
}

/**
 * Composed text styles — apply a whole ramp style by name, e.g.
 * `<span className={text.headline.emphasized}>`. Each style's two slots are
 * role-driven (see Typography.md): every `.standard` slot is the 400 weight
 * except Headline (500); `.emphasized` is Semibold or Bold by role.
 */
export const text = {
  largeTitle: ramp('largeTitle', 'standard', 'bold'),
  title1: ramp('title1', 'standard', 'bold'),
  title2: ramp('title2', 'standard', 'bold'),
  title3: ramp('title3', 'standard', 'bold'),
  headline: ramp('headline', 'emphasized', 'semibold'),
  body: ramp('body', 'standard', 'bold'),
  callout: ramp('callout', 'standard', 'bold'),
  control: ramp('control', 'standard', 'semibold'),
  caption: ramp('caption', 'standard', 'semibold'),
  footnote: ramp('footnote', 'standard', 'semibold')
}
