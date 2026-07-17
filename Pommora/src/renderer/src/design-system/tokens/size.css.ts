import { createGlobalTheme } from '@vanilla-extract/css'

/**
 * Size tokens — the single source for icon dimensions and control geometry.
 * Two scales, mirrored from Figma:
 *
 * - `icon.*` — the five-step glyph ladder (12 → 20). A named step routes here the
 *   way a colour name routes to color.css.ts; `<Icon size="md" />` resolves to it.
 * - `control.button.*` — per-component size aliases (`button-small/medium/large`).
 *   Each is a geometry bundle whose `icon` field *references* the icon ladder, so a
 *   control's glyph follows its size automatically. Large is exact from Figma
 *   (SEGMENTED · SYMBOL, Large/None); Small/Medium are proportional until pulled.
 */

// The glyph ladder — its own theme so the control bundles can point at its vars.
const iconScale = createGlobalTheme(':root', {
  icon: {
    xs: '12px',
    sm: '14px',
    md: '16px',
    lg: '18px',
    xl: '20px',
  },
})

// Per-component size aliases. Keyed `button-*` so a call site reads `size="button-large"`;
// `icon` references the ladder above (DRY linkage). Large is exact from Figma.
const controlScale = createGlobalTheme(':root', {
  control: {
    'button-small': {
      height: '24px',
      segmentHeight: '20px',
      paddingX: '4px',
      radius: '8px',
      segmentRadius: '4px',
      dividerHeight: '14px',
      icon: iconScale.icon.sm,
    },
    'button-medium': {
      height: '28px',
      segmentHeight: '24px',
      paddingX: '5px',
      radius: '10px',
      segmentRadius: '5px',
      dividerHeight: '18px',
      icon: iconScale.icon.md,
    },
    'button-large': {
      height: '32px',
      segmentHeight: '28px',
      paddingX: '8px',
      radius: '12px',
      segmentRadius: '6px',
      dividerHeight: '14px',
      icon: iconScale.icon.md,
    },
  },
})

/** One token object: `size.icon.md`, `size.control['button-large'].height`, … */
export const size = {
  icon: iconScale.icon,
  control: controlScale.control,
}

/** Icon-ladder step names — the values `<Icon size="…" />` accepts. */
export type IconSize = keyof typeof size.icon

/** Button size aliases — the values a segmented control's `size` prop accepts. */
export type ButtonSize = keyof typeof size.control
