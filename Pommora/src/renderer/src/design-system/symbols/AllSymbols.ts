import { icons as lucideIcons, type LucideIcon } from 'lucide-react'

/**
 * The FULL Lucide set — the Icon Picker's source, distinct from the 61-icon curated `icons` registry
 * (`./index`). The curated set is the app's semantic vocabulary; this is every glyph the user can pick
 * from. Built once at module load.
 */

/** A Lucide PascalCase component name → its canonical kebab id. Validated against lucide-react's own
 *  per-icon dist filenames (1714/1715 exact; the sole outlier is a legacy alias with no canonical
 *  file). Digits split from letters on both sides, so `Grid3x3 → grid-3-x-3`, `Columns3Cog →
 *  columns-3-cog`; consecutive capitals break before the final word, so `AArrowDown → a-arrow-down`. */
export function toKebabIconId(name: string): string {
  return name
    .replace(/([a-z0-9])([A-Z])/g, '$1-$2')
    .replace(/([A-Z]+)([A-Z][a-z])/g, '$1-$2')
    .replace(/([a-zA-Z])([0-9])/g, '$1-$2')
    .replace(/([0-9])([a-zA-Z])/g, '$1-$2')
    .toLowerCase()
}

export interface IconEntry {
  id: string
  Glyph: LucideIcon
}

/** Every Lucide icon, kebab-keyed, de-duped by id, sorted. */
export const ALL_ICONS: IconEntry[] = (() => {
  const seen = new Set<string>()
  const out: IconEntry[] = []
  for (const [pascal, Glyph] of Object.entries(lucideIcons)) {
    const id = toKebabIconId(pascal)
    if (seen.has(id)) continue
    seen.add(id)
    out.push({ id, Glyph })
  }
  return out.sort((a, b) => a.id.localeCompare(b.id))
})()

const BY_ID = new Map(ALL_ICONS.map((e) => [e.id, e.Glyph]))

/** Resolve any Lucide id to its component, or undefined if unknown. */
export const lucideGlyph = (id: string): LucideIcon | undefined => BY_ID.get(id)

/** Dash/space-insensitive substring search over ids ("arrow up" ⇒ `arrow-up-down`). Empty ⇒ all. */
export function searchIcons(query: string): IconEntry[] {
  const q = query.trim().toLowerCase().replace(/[\s-]/g, '')
  if (!q) return ALL_ICONS
  return ALL_ICONS.filter((e) => e.id.replace(/-/g, '').includes(q))
}
