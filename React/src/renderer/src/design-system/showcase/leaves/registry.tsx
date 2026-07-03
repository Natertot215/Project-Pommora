import type { IconName } from '@renderer/design-system/symbols'
import { ColorsLeaf } from './ColorsLeaf'
import { TypographyLeaf } from './TypographyLeaf'
import { IconsLeaf } from './IconsLeaf'
import { ChipsLeaf } from './ChipsLeaf'
import { MenuLeaf } from './MenuLeaf'
import { GlassLeaf } from './GlassLeaf'
import { InteractionsLeaf } from './InteractionsLeaf'
import { CalendarPickerLeaf } from './CalendarPickerLeaf'
import { StubLeaf } from './StubLeaf'

// The leaf catalog — the single source of which leaves the showcase has. Adding a
// component to the showcase is one entry here plus its leaf module; the sidebar and
// content pane both derive entirely from this list.

export type SectionId = 'foundations' | 'components' | 'materials' | 'interactions'

export type Leaf = {
  id: string
  label: string
  icon: IconName
  section: SectionId
  render: () => React.JSX.Element
}

/** Section display order + labels (mirrors the app's sectioned sidebar). */
export const SECTIONS: ReadonlyArray<{ id: SectionId; label: string }> = [
  { id: 'foundations', label: 'Foundations' },
  { id: 'components', label: 'Components' },
  { id: 'materials', label: 'Materials' },
  { id: 'interactions', label: 'Interactions' }
]

export const LEAVES: readonly Leaf[] = [
  { id: 'colors', label: 'Colors', icon: 'palette', section: 'foundations', render: () => <ColorsLeaf /> },
  { id: 'typography', label: 'Typography', icon: 'type', section: 'foundations', render: () => <TypographyLeaf /> },
  { id: 'icons', label: 'Icons', icon: 'shapes', section: 'foundations', render: () => <IconsLeaf /> },
  { id: 'chips', label: 'Chips', icon: 'tag', section: 'components', render: () => <ChipsLeaf /> },
  { id: 'menu', label: 'Menu', icon: 'ellipsis-vertical', section: 'components', render: () => <MenuLeaf /> },
  { id: 'calendar-picker', label: 'CalendarPicker', icon: 'calendar', section: 'components', render: () => <CalendarPickerLeaf /> },
  { id: 'switch', label: 'Switch', icon: 'square-check', section: 'components', render: () => <StubLeaf name="Switch" /> },
  { id: 'picker-menu', label: 'PickerMenu', icon: 'dots', section: 'components', render: () => <StubLeaf name="PickerMenu" /> },
  { id: 'overflow-scroll', label: 'OverflowScroll', icon: 'grip-horizontal', section: 'components', render: () => <StubLeaf name="OverflowScroll" /> },
  { id: 'notched-pane', label: 'NotchedPane', icon: 'panel-right', section: 'components', render: () => <StubLeaf name="NotchedPane" /> },
  { id: 'glass', label: 'Glass', icon: 'layers', section: 'materials', render: () => <GlassLeaf /> },
  { id: 'interactions', label: 'Interaction Lab', icon: 'arrow-up-down', section: 'interactions', render: () => <InteractionsLeaf /> }
]

/** Resolve a hash id to a leaf, falling back to the first leaf. */
export function leafById(id: string): Leaf {
  return LEAVES.find((l) => l.id === id) ?? LEAVES[0]
}
