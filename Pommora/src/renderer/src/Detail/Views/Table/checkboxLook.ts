import type { CSSProperties } from 'react'
import { tint } from '@renderer/design-system/tokens/tint'
import { solidColorCss } from './solidColor'

/** The inline style for a checkbox/group-on box at a given checked state + property colour. An empty
 *  box stays neutral grey (the caller adds `chipColor.default`); a checked box tints its colour — a set
 *  solid, else the configured accent via `var(--accent)` so it matches the switch look and resolves for
 *  a palette OR system accent. The check glyph always reads label-control. */
export function checkboxBoxStyle(checked: boolean, color: string | undefined): CSSProperties {
  return checked ? { ...tint(color ? solidColorCss(color) : 'var(--accent)'), color: 'var(--label-control)' } : { color: 'var(--label-control)' }
}
