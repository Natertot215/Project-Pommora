import {
  IconAdjustmentsHorizontal,
  IconArrowsUpDown,
  IconCalendarMonth,
  IconCheck,
  IconChevronCompactDown,
  IconChevronCompactUp,
  IconCircleDashed,
  IconCirclePlus,
  IconClockHour3,
  IconCopy,
  IconDots,
  IconDotsVertical,
  IconEye,
  IconEyeClosed,
  IconFileImport,
  IconFileText,
  IconFilter2,
  IconGripHorizontal,
  IconGripVertical,
  IconHash,
  IconHeart,
  IconHome,
  IconLayoutDashboard,
  IconLayoutSidebarRight,
  IconMap,
  IconMinus,
  IconPalette,
  IconPlus,
  IconServer,
  IconSquareCheck,
  IconStack2,
  IconTag,
  IconTriangleSquareCircle,
  IconTypography,
  IconX
} from '@tabler/icons-react'
import {
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  FolderClosed,
  FolderOpen,
  GalleryVerticalEnd,
  LayoutGrid,
  Link,
  Link2,
  LogOut,
  SquarePlus
} from 'lucide-react'
import type { ComponentPropsWithoutRef, ComponentType } from 'react'
import { size as sizeTokens, type IconSize } from '../tokens/size.css'
import { SquareDashed } from './SquareDashed'

/** The prop contract the seam renders through — size/stroke plus pass-through SVG props (events,
 *  aria) so callsites keep their handlers. The libraries spell the stroke-width prop differently
 *  (Tabler `stroke`, Lucide `strokeWidth`), so no one component type satisfies both: entries are
 *  cast through the helpers, and the Icon adapter guarantees each source only ever receives its
 *  own spelling. */
type GlyphProps = {
  size?: number | string
  strokeWidth?: number | string
  stroke?: number | string
} & Omit<ComponentPropsWithoutRef<'svg'>, 'stroke' | 'strokeWidth'>
type Glyph = ComponentType<GlyphProps>

/** Tabler registrations render at this stroke (Tabler ships 2) — Nathan's ratified default. The
 *  Lucide keeps stay at their library default; the keeps were kept for how they look today. */
const TABLER_STROKE = 1.75

// ComponentType<never> admits any component; the cast to Glyph is the seam's controlled boundary.
const t = (glyph: ComponentType<never>): { glyph: Glyph; tabler: boolean } => ({ glyph: glyph as Glyph, tabler: true })
const l = (glyph: ComponentType<never>): { glyph: Glyph; tabler: false } => ({ glyph: glyph as Glyph, tabler: false })

/**
 * PommoraIcons — the curated registry, the single source of which icons exist in the app.
 * Mixed by design (spec: Planning/7-2 PommoraIcons inventory): Tabler is the default set,
 * a handful of ratified Lucide keeps stay, and customs are first-party SVGs in the same slot
 * shape. Keys are PommoraIcons names — the app's own vocabulary (inherited from the Lucide
 * era; stored frontmatter never matched it, so keys rename freely when a glyph changes
 * identity). This registry mirrors `Symbols.md` — add a name there, then a line here.
 */
export const icons = {
  house: t(IconHome),
  calendar: t(IconCalendarMonth),
  clock: t(IconClockHour3),
  'gallery-vertical-end': l(GalleryVerticalEnd),
  'folder-closed': l(FolderClosed),
  'folder-open': l(FolderOpen),
  'file-text': t(IconFileText),
  'layout-grid': l(LayoutGrid),
  check: t(IconCheck),
  'circle-dashed': t(IconCircleDashed),
  minus: t(IconMinus),
  'sliders-horizontal': t(IconAdjustmentsHorizontal),
  // The cardinal chevrons are Lucide — Nathan's ruling (07-02): Lucide is THE house chevron
  // (Tabler's draws visibly smaller in the same box). Compacts stay Tabler (no Lucide twin).
  'chevron-left': l(ChevronLeft),
  'chevron-right': l(ChevronRight),
  'chevron-up': l(ChevronUp),
  'chevron-down': l(ChevronDown),
  'chevron-compact-up': t(IconChevronCompactUp),
  'chevron-compact-down': t(IconChevronCompactDown),
  map: t(IconMap),
  x: t(IconX),
  plus: t(IconPlus),
  'circle-plus': t(IconCirclePlus),
  'square-plus': l(SquarePlus),
  'ellipsis-vertical': t(IconDotsVertical),
  dots: t(IconDots),
  tag: t(IconTag),
  'panel-right': t(IconLayoutSidebarRight),
  'square-dashed': l(SquareDashed),
  copy: t(IconCopy),
  'arrow-up-down': t(IconArrowsUpDown),
  'log-out': l(LogOut),
  palette: t(IconPalette),
  type: t(IconTypography),
  shapes: t(IconTriangleSquareCircle),
  layers: t(IconStack2),
  'grip-vertical': t(IconGripVertical),
  'grip-horizontal': t(IconGripHorizontal),
  heart: t(IconHeart),
  hash: t(IconHash),
  'square-check': t(IconSquareCheck),
  import: t(IconFileImport),
  link: l(Link),
  'link-2': l(Link2),
  server: t(IconServer),
  eye: t(IconEye),
  'eye-off': t(IconEyeClosed),
  'layout-dashboard': t(IconLayoutDashboard),
  'list-filter': t(IconFilter2)
} satisfies Record<string, { glyph: Glyph; tabler: boolean }>

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
 *   `font-size` while the glyph stays at `1em`, so one source (`size.icon.*`) drives it.
 * - **Default** (`1em`) follows the context font-size (the type scale).
 * - **Number / CSS length** (`size={18}`) passes straight through as an escape hatch.
 * Colour follows `currentColor` in every case. `strokeWidth` is normalized across sources:
 * Tabler spells the width prop `stroke`, Lucide `strokeWidth` — callers only ever say
 * `strokeWidth`, the seam translates (and applies the Tabler 1.75 default).
 */
export function Icon({
  name,
  size = '1em',
  style,
  strokeWidth,
  ...rest
}: {
  name: IconName
  size?: IconSize | number | string
  strokeWidth?: number | string
} & Omit<ComponentPropsWithoutRef<'svg'>, 'name' | 'stroke' | 'strokeWidth'>): React.JSX.Element {
  const { glyph: Glyph, tabler } = icons[name]
  const stroke: Partial<GlyphProps> = tabler
    ? { stroke: strokeWidth ?? TABLER_STROKE }
    : strokeWidth !== undefined
      ? { strokeWidth }
      : {}
  if (isIconSize(size)) {
    return <Glyph size="1em" {...stroke} {...rest} style={{ ...style, fontSize: iconSizeVars[size] }} />
  }
  return <Glyph size={size} {...stroke} {...rest} style={style} />
}
