// The chip tint recipe — kept in a PLAIN module (not a *.css.ts) so it can be a
// reusable function export. vanilla-extract serializes every export of a *.css.ts
// into a virtual CSS module and a function throws, so `tint` can't live in chip.css.ts.
// chip.css.ts uses it to build chipColor.*; the showcase uses it for the accent chip
// via tint('var(--accent)').
import { vars as colorVars } from './color.css'

const labelPrimary = colorVars.color.label.primary

/**
 * One formula per base color: fill = base @ 60% · stroke = base @ 40% · text =
 * label-primary + base @ 15%. `color-mix(… X%, transparent)` = the base at X% alpha;
 * the text mixes 15% base into label-primary (Figma's Tint/Quinary wash).
 */
export const tint = (base: string): { background: string; borderColor: string; color: string } => ({
  background: `color-mix(in srgb, ${base} 60%, transparent)`,
  borderColor: `color-mix(in srgb, ${base} 40%, transparent)`,
  color: `color-mix(in srgb, ${base} 15%, ${labelPrimary})`
})
