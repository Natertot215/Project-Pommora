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
  Minus,
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
  PanelRight,
  SquareDashed,
  CircleX,
  Copy,
  ArrowLeftRight,
  ArrowUpDown,
  LogIn,
  LogOut,
  KeyRound,
  Lock,
  SquarePlus,
  Palette,
  Type,
  Shapes,
  Layers,
  GripVertical,
  type LucideIcon,
  type LucideProps
} from 'lucide-react'
import { size as sizeTokens, type IconSize } from '../tokens/size.css'

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
  minus: Minus,
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
  'panel-right': PanelRight,
  'square-dashed': SquareDashed,
  'circle-x': CircleX,
  copy: Copy,
  'arrow-left-right': ArrowLeftRight,
  'arrow-up-down': ArrowUpDown,
  'log-in': LogIn,
  'log-out': LogOut,
  'key-round': KeyRound,
  lock: Lock,
  'square-plus': SquarePlus,
  palette: Palette,
  type: Type,
  shapes: Shapes,
  layers: Layers,
  'grip-vertical': GripVertical
} satisfies Record<string, LucideIcon>

export type IconName = keyof typeof icons

/** Coerce an arbitrary value (e.g. a frontmatter `icon` string) to a known IconName, or undefined if it isn't one. */
export const asIconName = (value: unknown): IconName | undefined =>
  typeof value === 'string' && value in icons ? (value as IconName) : undefined

/** As `asIconName`, but falls back to a default when the value isn't a known icon. */
export const iconNameOr = (value: unknown, fallback: IconName): IconName => asIconName(value) ?? fallback

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
