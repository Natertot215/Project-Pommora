import type { CSSProperties } from 'react'
import { tint } from '@renderer/design-system/tokens/tint'
import { solidColorCss } from './solidColor'

/** The inline style for a checkbox/group-on box at a given checked state + property colour. An empty
 *  box stays neutral grey (the caller adds `chipColor.default`); a checked box tints its colour — a set
 *  solid, else the configured accent via `var(--accent)` so it matches the switch look and resolves for
 *  a palette OR system accent. The check glyph always reads label-control. `verticalAlign: middle`
 *  pins the box's line box the SAME whether or not it holds the check glyph, so toggling a cell never
 *  changes the row height (an empty inline-flex box otherwise sits on the baseline and adds descender). */
export function checkboxBoxStyle(checked: boolean, color: string | undefined): CSSProperties {
  const base: CSSProperties = { verticalAlign: 'middle', color: 'var(--label-control)' }
  return checked ? { ...tint(color ? solidColorCss(color) : 'var(--accent)'), ...base } : base
}
