import {
  House,
  Calendar,
  Clock,
  GalleryVerticalEnd,
  FolderClosed,
  FolderOpen,
  FileText,
  LayoutGrid,
  Check,
  CircleDashed,
  SlidersHorizontal,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  ChevronDown,
  Map as MapIcon,
  X,
  Plus,
  EllipsisVertical,
  Tag,
  PanelLeft,
  SquareDashed,
  CircleX,
  Copy,
  ArrowLeftRight,
  ArrowUpDown,
  type LucideIcon,
  type LucideProps
} from 'lucide-react'

/**
 * Curated icon set — Lucide (https://lucide.dev/icons). The single source of
 * which icons exist in the app; keys are the lucide.dev names (kebab-case).
 * This registry mirrors `Symbols.md` — add a name there, then import it above
 * and add a line here. Tree-shaking keeps only these in the bundle.
 */
export const icons = {
  house: House,
  calendar: Calendar,
  clock: Clock,
  'gallery-vertical-end': GalleryVerticalEnd,
  'folder-closed': FolderClosed,
  'folder-open': FolderOpen,
  'file-text': FileText,
  'layout-grid': LayoutGrid,
  check: Check,
  'circle-dashed': CircleDashed,
  'sliders-horizontal': SlidersHorizontal,
  'chevron-left': ChevronLeft,
  'chevron-right': ChevronRight,
  'chevron-up': ChevronUp,
  'chevron-down': ChevronDown,
  map: MapIcon,
  x: X,
  plus: Plus,
  'ellipsis-vertical': EllipsisVertical,
  tag: Tag,
  'panel-left': PanelLeft,
  'square-dashed': SquareDashed,
  'circle-x': CircleX,
  copy: Copy,
  'arrow-left-right': ArrowLeftRight,
  'arrow-up-down': ArrowUpDown
} satisfies Record<string, LucideIcon>

export type IconName = keyof typeof icons

/** Render a curated icon by name: `<Icon name="folder-closed" size={15} />`. */
export function Icon({ name, size = 16, ...rest }: { name: IconName } & LucideProps): React.JSX.Element {
  const Glyph = icons[name]
  return <Glyph size={size} {...rest} />
}
