import {
  ArrowUpDown,
  Calendar,
  CalendarDays,
  ChartGantt,
  Check,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ChevronsUpDown,
  ChevronUp,
  CircleDashed,
  Clock,
  Columns3Cog,
  Copy,
  Ellipsis,
  EllipsisVertical,
  Eye,
  EyeOff,
  FileText,
  FolderClosed,
  FolderOpen,
  GalleryVerticalEnd,
  GripHorizontal,
  GripVertical,
  Hash,
  Heart,
  House,
  Import,
  LayoutDashboard,
  LayoutGrid,
  LayoutPanelLeft,
  Layers,
  Layers2,
  Link,
  Link2,
  ListFilter,
  LogOut,
  type LucideIcon,
  type LucideProps,
  Map as MapIcon,
  Minus,
  Palette,
  PanelRight,
  Plus,
  Send,
  Server,
  Shapes,
  SlidersHorizontal,
  SquareCheck,
  SquareDashed,
  SquarePlus,
  Tag,
  Tags,
  TextAlignJustify,
  Type,
  X
} from 'lucide-react'
import type { EntityIconKind } from '@shared/types'
import { CardsGrid, ListRounded, TableWide } from './customGlyphs'
import { size as sizeTokens, type IconSize } from '../tokens/size.css'

/**
 * Curated icon set — Lucide (https://lucide.dev/icons). The single source of which icons exist in
 * the app; keys are the app's icon vocabulary (mostly the lucide.dev name). This registry mirrors
 * `Symbols.md` — add a name there, then import it above and add a line here. Tree-shaking keeps
 * only these in the bundle. **Tabler (`@tabler/icons-react`) stays installed as a second source we
 * can pull from** — to use one, import its `Icon*` component and add the entry (it renders through
 * the same seam; Tabler's default stroke is 2, so pass `strokeWidth={1.75}` to match Lucide's weight).
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
  minus: Minus,
  tags: Tags,
  'sliders-horizontal': SlidersHorizontal,
  'chevron-left': ChevronLeft,
  'chevron-right': ChevronRight,
  'chevron-up': ChevronUp,
  'chevron-down': ChevronDown,
  map: MapIcon,
  x: X,
  plus: Plus,
  'square-plus': SquarePlus,
  'ellipsis-vertical': EllipsisVertical,
  dots: Ellipsis,
  tag: Tag,
  'panel-right': PanelRight,
  'square-dashed': SquareDashed,
  copy: Copy,
  'arrow-up-down': ArrowUpDown,
  'log-out': LogOut,
  palette: Palette,
  type: Type,
  shapes: Shapes,
  layers: Layers,
  'grip-vertical': GripVertical,
  'grip-horizontal': GripHorizontal,
  heart: Heart,
  hash: Hash,
  'square-check': SquareCheck,
  import: Import,
  link: Link,
  'link-2': Link2,
  send: Send,
  server: Server,
  eye: Eye,
  'eye-off': EyeOff,
  'layout-dashboard': LayoutDashboard,
  'list-filter': ListFilter,
  'calendar-days': CalendarDays,
  'chart-gantt': ChartGantt,
  'chevrons-up-down': ChevronsUpDown,
  'layout-panel-left': LayoutPanelLeft,
  'text-align-justify': TextAlignJustify,
  'layers-2': Layers2,
  table: TableWide,
  'list-rounded': ListRounded,
  'cards-grid': CardsGrid,
  'columns-3-cog': Columns3Cog
} satisfies Record<string, LucideIcon>

export type IconName = keyof typeof icons

/** Coerce an arbitrary value (e.g. a frontmatter `icon` string) to a known IconName, or undefined if it isn't one. */
export const asIconName = (value: unknown): IconName | undefined =>
  typeof value === 'string' && value in icons ? (value as IconName) : undefined

/** As `asIconName`, but falls back to a default when the value isn't a known icon. */
export const iconNameOr = (value: unknown, fallback: IconName): IconName => asIconName(value) ?? fallback

/** Per-entity-kind default icon — the seed for `personalization.defaultIcons`. One source for the
 *  sidebar, banners, the table, and the connection autocomplete (was this same literal copied across
 *  all of them). A nexus can override a kind's default; an entity's own `icon` overrides that in turn. */
export const DEFAULT_ENTITY_ICONS: Record<EntityIconKind, IconName> = {
  collection: 'gallery-vertical-end',
  set: 'folder-closed',
  area: 'layout-grid',
  topic: 'layout-grid',
  project: 'layout-grid',
  page: 'file-text'
}

/** A kind's default icon: the nexus's personalization override when it's a real icon, else the seed.
 *  A per-entity `icon` is layered on by the caller (iconNameOr / folderAwareIcons). */
export function defaultEntityIcon(
  kind: EntityIconKind,
  overrides?: Partial<Record<EntityIconKind, string>>
): IconName {
  return iconNameOr(overrides?.[kind], DEFAULT_ENTITY_ICONS[kind])
}

const iconSizeVars = sizeTokens.icon
const isIconSize = (v: unknown): v is IconSize => typeof v === 'string' && v in iconSizeVars

/**
 * Render a curated icon by name: `<Icon name="folder-closed" />`.
 *
 * Size resolution:
 * - **Named step** (`size="md"`) routes to the icon-size token — set as the glyph's
 *   `font-size` while lucide stays at `1em`, so one source (`size.icon.*`) drives it.
 * - **Default** (`1em`) follows the context font-size (the type scale).
 * - **Number / CSS length** (`size={18}`) passes straight through as an escape hatch.
 * Colour follows `currentColor` in every case.
 */
export function Icon({
  name,
  size = '1em',
  style,
  ...rest
}: { name: IconName; size?: IconSize | LucideProps['size'] } & Omit<LucideProps, 'size'>): React.JSX.Element {
  const Glyph = icons[name]
  if (isIconSize(size)) {
    return <Glyph size="1em" {...rest} style={{ ...style, fontSize: iconSizeVars[size] }} />
  }
  return <Glyph size={size} {...rest} style={style} />
}
