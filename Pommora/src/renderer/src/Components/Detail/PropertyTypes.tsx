import type { PropertyType } from '@shared/properties'
import { Icon, type IconName } from '@renderer/design-system/symbols'
import { DashIcon } from './DashIcon'

/**
 * The single source for per-property-type presentation: the user-facing label + the standard Pommora
 * icon (catalogued in Features/Icons.md). `creatable` flags the user-pickable set, in picker order —
 * `context` is tier-only and `last_edited_time` is auto-managed. Types still awaiting a glyph carry no
 * `icon` and fall back to DashIcon.
 */
interface TypeMeta {
  label: string
  icon?: IconName
  creatable?: boolean
}

const PROPERTY_TYPES: Record<PropertyType, TypeMeta> = {
  number: { label: 'Number', icon: 'hash', creatable: true },
  checkbox: { label: 'Checkbox', icon: 'square-check', creatable: true },
  datetime: { label: 'Date', icon: 'calendar', creatable: true },
  select: { label: 'Select', icon: 'send', creatable: true },
  multi_select: { label: 'Multi-Select', icon: 'tags', creatable: true },
  status: { label: 'Status', icon: 'circle-dashed', creatable: true },
  url: { label: 'Link', icon: 'link', creatable: true },
  file: { label: 'File', icon: 'import', creatable: true },
  context: { label: 'Context', icon: 'layout-grid' },
  last_edited_time: { label: 'Last edited' }
}

export const propertyTypeLabel = (type: PropertyType): string => PROPERTY_TYPES[type].label

export const CREATABLE_TYPES = (Object.keys(PROPERTY_TYPES) as PropertyType[]).filter(
  (t) => PROPERTY_TYPES[t].creatable
)

// Title isn't a user PropertyType (it's the reserved heading column), but it needs the same glyph
// vocabulary — its icon lives here so every surface renders it from one source.
const TITLE_META: TypeMeta = { label: 'Title', icon: 'text-align-justify' }

export function PropertyTypeIcon({ type, size = 16 }: { type: PropertyType | 'title'; size?: number }): React.JSX.Element {
  const name = (type === 'title' ? TITLE_META : PROPERTY_TYPES[type]).icon
  return name ? <Icon name={name} size={size} /> : <DashIcon />
}
