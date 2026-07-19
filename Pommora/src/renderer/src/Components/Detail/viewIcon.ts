import type { IconName } from '@renderer/design-system/symbols'
import type { ViewType } from '@shared/views'

/** The icon a view should carry after a type switch: the NEW type's default glyph when the view still
 *  wears the OLD type's default glyph (or a legacy table glyph, or no icon) — i.e. was never
 *  customized — else undefined to KEEP the user's custom icon. Legacy `'tablecells'` sidecars count
 *  as the table default. */
export function iconForTypeSwitch(
  currentIcon: string | undefined,
  oldType: ViewType,
  newType: ViewType,
  glyphOf: Record<ViewType, IconName>,
): IconName | undefined {
  const wasDefault =
    currentIcon === undefined ||
    currentIcon === glyphOf[oldType] ||
    (oldType === 'table' && currentIcon === 'tablecells')
  return wasDefault ? glyphOf[newType] : undefined
}
