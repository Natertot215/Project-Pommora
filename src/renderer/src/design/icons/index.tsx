import {
  House,
  Calendar,
  Clock,
  Layers,
  Folder,
  FolderClosed,
  FileText,
  LayoutGrid,
  Check,
  Circle,
  type LucideIcon,
  type LucideProps
} from 'lucide-react'

/**
 * Curated icon set — Lucide (https://lucide.dev/icons). The single source of
 * which icons exist in the app; keys are the lucide.dev names (kebab-case).
 *
 * To add an icon: list its name in Symbols.md, then import it above and add a
 * line here. Tree-shaking means only these ship — the full set never bundles.
 */
export const icons = {
  house: House,
  calendar: Calendar,
  clock: Clock,
  layers: Layers,
  folder: Folder,
  'folder-closed': FolderClosed,
  'file-text': FileText,
  'layout-grid': LayoutGrid,
  check: Check,
  circle: Circle
} satisfies Record<string, LucideIcon>

export type IconName = keyof typeof icons

/** Render a curated icon by name: `<Icon name="folder" size={15} />`. */
export function Icon({ name, size = 16, ...rest }: { name: IconName } & LucideProps): React.JSX.Element {
  const Glyph = icons[name]
  return <Glyph size={size} {...rest} />
}
