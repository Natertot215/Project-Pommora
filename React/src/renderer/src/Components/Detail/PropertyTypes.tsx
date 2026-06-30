import { Hash, SquareCheck, CalendarDays, CircleDashed, Link, Import, Link2, type LucideIcon } from 'lucide-react'
import type { PropertyType } from '@shared/properties'
import { DashIcon } from './DashIcon'

/**
 * The single source for per-property-type presentation: the user-facing label + the standard Pommora
 * icon (catalogued in Features/Icons.md). `creatable` flags the user-pickable set, in picker order —
 * `relation` is tier-only, `last_edited_time` is auto-managed, and `date` is the read-only variant of
 * the creatable `datetime`. Types still awaiting a glyph carry no `icon` and fall back to DashIcon.
 */
interface TypeMeta {
  label: string
  icon?: LucideIcon
  creatable?: boolean
}

const PROPERTY_TYPES: Record<PropertyType, TypeMeta> = {
  number: { label: 'Number', icon: Hash, creatable: true },
  checkbox: { label: 'Checkbox', icon: SquareCheck, creatable: true },
  datetime: { label: 'Date', icon: CalendarDays, creatable: true },
  select: { label: 'Select', creatable: true },
  multi_select: { label: 'Multi-Select', creatable: true },
  status: { label: 'Status', icon: CircleDashed, creatable: true },
  url: { label: 'Link', icon: Link, creatable: true },
  file: { label: 'File', icon: Import, creatable: true },
  date: { label: 'Date', icon: CalendarDays },
  relation: { label: 'Relation', icon: Link2 },
  last_edited_time: { label: 'Last edited' }
}

export const propertyTypeLabel = (type: PropertyType): string => PROPERTY_TYPES[type].label

export const CREATABLE_TYPES = (Object.keys(PROPERTY_TYPES) as PropertyType[]).filter(
  (t) => PROPERTY_TYPES[t].creatable
)

export function PropertyTypeIcon({ type, size = 16 }: { type: PropertyType; size?: number }): React.JSX.Element {
  const Icon = PROPERTY_TYPES[type].icon
  return Icon ? <Icon size={size} /> : <DashIcon />
}
