import {
  AppWindow,
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
  ClockPlus,
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
  Grid3x2,
  GripHorizontal,
  GripVertical,
  Hash,
  Heart,
  History,
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
  Maximize2,
  Minus,
  Palette,
  PanelRight,
  Plus,
  Scaling,
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
  X,
} from 'lucide-react'
import { forwardRef } from 'react'
import type { EntityIconKind } from '@shared/types'
import { CardsGrid, ListRounded, LockSolid, ProgressCheck } from './customGlyphs'
import { lucideGlyph } from './AllSymbols'
import { size as sizeTokens, type IconSize } from '../tokens/size.css'

/**
 * Curated icon set — Lucide (https://lucide.dev/icons). The single source of which icons exist in
 * the app; keys are the app's icon vocabulary (mostly the lucide.dev name). This registry mirrors
 * `Symbols.md` — add a name there, then import it above and add a line here. Tree-shaking keeps
 * only these in the bundle. **Tabler (`@tabler/icons-react`) stays installed as a second source we
 * can pull from** — to use one, import its `Icon*` component and add the entry (it renders through
 * the same seam; Lucide's and Tabler's default stroke are both 2, so they sit at the same weight with
 * no override).
 */
export const icons = {
  house: House,
  calendar: Calendar,
  clock: Clock,
  'clock-plus': ClockPlus,
  history: History,
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
  'app-window': AppWindow,
  map: MapIcon,
  'maximize-2': Maximize2,
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
  scaling: Scaling,
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
  table: Grid3x2,
  'list-rounded': ListRounded,
  'cards-grid': CardsGrid,
  'progress-check': ProgressCheck,
  'columns-3-cog': Columns3Cog,
  lock: LockSolid,
} satisfies Record<string, LucideIcon>

export type IconName = keyof typeof icons

/** Coerce an arbitrary value to a CURATED IconName, or undefined if it isn't one of the 61. */
export const asIconName = (value: unknown): IconName | undefined =>
  typeof value === 'string' && value in icons ? (value as IconName) : undefined

/** A stored icon id if it's RENDERABLE (curated OR any full-set Lucide id), else undefined — for the
 *  optional-icon sites that show nothing when unset (vs `iconNameOr`, which always resolves a fallback). */
export const asRenderableIcon = (value: unknown): string | undefined =>
  typeof value === 'string' && (value in icons || lucideGlyph(value) !== undefined)
    ? value
    : undefined

/** Resolve a stored icon to a renderable symbol id — kept if it's ANY Lucide id (curated OR the full
 *  set, so a user's arbitrary pick survives), else the fallback. Returns a bare string; `Icon` renders it. */
export const iconNameOr = (value: unknown, fallback: IconName): string =>
  typeof value === 'string' && (value in icons || lucideGlyph(value) !== undefined)
    ? value
    : fallback

/** Per-entity-kind default icon — the seed for `personalization.defaultIcons`. One source for the
 *  sidebar, banners, the table, and the connection autocomplete (was this same literal copied across
 *  all of them). A nexus can override a kind's default; an entity's own `icon` overrides that in turn. */
export const DEFAULT_ENTITY_ICONS: Record<EntityIconKind, IconName> = {
  collection: 'gallery-vertical-end',
  set: 'folder-closed',
  area: 'layout-grid',
  topic: 'layout-grid',
  project: 'layout-grid',
  page: 'file-text',
}

/** A kind's default icon: the nexus's personalization override when it's a real icon, else the seed.
 *  A per-entity `icon` is layered on by the caller (iconNameOr / folderAwareIcons). */
export function defaultEntityIcon(
  kind: EntityIconKind,
  overrides?: Partial<Record<EntityIconKind, string>>,
): IconName {
  // Kind DEFAULTS stay curated (a sensible seed glyph); a per-entity arbitrary pick is layered on by
  // the caller via iconNameOr / folderAwareIcons, which keep the full set.
  return asIconName(overrides?.[kind]) ?? DEFAULT_ENTITY_ICONS[kind]
}

const iconSizeVars = sizeTokens.icon
const isIconSize = (v: unknown): v is IconSize => typeof v === 'string' && v in iconSizeVars

/**
 * Render an icon by id: `<Icon name="folder-closed" />`. Resolves the CURATED registry first, then the
 * full Lucide set (a user's arbitrary pick), falling back to the dashed-square placeholder if neither
 * matches — so `name` is a bare `string`, not just a curated `IconName`.
 *
 * Size resolution:
 * - **Named step** (`size="md"`) routes to the icon-size token — set as the glyph's
 *   `font-size` while lucide stays at `1em`, so one source (`size.icon.*`) drives it.
 * - **Default** (`1em`) follows the context font-size (the type scale).
 * - **Number / CSS length** (`size={18}`) passes straight through as an escape hatch.
 * Colour follows `currentColor` in every case.
 */
export const Icon = forwardRef<
  SVGSVGElement,
  { name: string; size?: IconSize | LucideProps['size'] } & Omit<LucideProps, 'size'>
>(function Icon({ name, size = '1em', style, ...rest }, ref): React.JSX.Element {
  const Glyph =
    (icons as Record<string, LucideIcon>)[name] ?? lucideGlyph(name) ?? icons['square-dashed']
  if (isIconSize(size)) {
    return (
      <Glyph ref={ref} size="1em" {...rest} style={{ ...style, fontSize: iconSizeVars[size] }} />
    )
  }
  return <Glyph ref={ref} size={size} {...rest} style={style} />
})
