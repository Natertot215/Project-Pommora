import type { ReactNode } from 'react'
import type { CollectionNode, SetNode } from '@shared/types'
import { type PropertyDefinition, RESERVED_PROPERTY_ID } from '@shared/properties'
import type { SavedView } from '@shared/views'
import { Icon } from '@renderer/design-system/symbols'
import { useSession } from '../../store'
import { MenuItem, MenuPaneTopRow, MenuScrollFrame } from '../../design-system/components/menu'
import { flushTrailing } from '../../design-system/components/menu/menu.css'
import { resolveColumns } from '../../Detail/Views/pipeline/columns'
import { columnLabel } from '../../Detail/Views/Table/columnLabel'
import { useActiveView } from '../../Detail/Views/useActiveView'
import { useSaveView } from '@renderer/Embeds/ViewEmbedScope'
import { PaneDnd, RowShell, usePaneRegions } from './paneDnd'
import type { PaneDrop, PaneRow } from './paneDndModel'
import { hiddenListIds, hiddenPaneSlot, hideShown, placeInShown, unhide } from './hiddenPaneModel'
import { PropertyTypeIcon } from './PropertyTypes'
import { cx } from '../../design-system/cx'
import * as s from './settingsPane.css'

/** A row's leading glyph: schema props wear their type icon; Title and the tiers wear the reserved
 *  glyph; Modified falls back with its type meta. */
function rowIcon(id: string, schema: PropertyDefinition[]): ReactNode {
  const def = schema.find((d) => d.id === id)
  if (def) return <PropertyTypeIcon type={def.type} size={s.ICON.doc} />
  if (id === RESERVED_PROPERTY_ID.title) return <PropertyTypeIcon type="title" size={s.ICON.doc} />
  if (id === RESERVED_PROPERTY_ID.modifiedAt)
    return <PropertyTypeIcon type="last_edited_time" size={s.ICON.doc} />
  return <PropertyTypeIcon type="context" size={s.ICON.doc} />
}

/** The eye toggle — rest shows the current state's glyph, hover previews the toggle: a hidden
 *  row runs the same pair in reverse (Nathan's spec). Both glyphs mount; CSS swaps them. */
function EyeToggle({
  hidden,
  name,
  onToggle,
}: {
  hidden: boolean
  name: string
  onToggle: () => void
}): React.JSX.Element {
  return (
    <button
      type="button"
      className={s.eyeButton}
      aria-label={`${hidden ? 'Show' : 'Hide'} ${name}`}
      onClick={(e) => {
        e.stopPropagation()
        onToggle()
      }}
    >
      <span className={s.eyeRestGlyph}>
        <Icon name={hidden ? 'eye-off' : 'eye'} size={s.ICON.eye} />
      </span>
      <span className={s.eyeHoverGlyph}>
        <Icon name={hidden ? 'eye' : 'eye-off'} size={s.ICON.eye} />
      </span>
    </button>
  )
}

/** The two zones — the shown rows (the one drag region, in view order: Title, tiers, and properties
 *  together) then the hidden block. Lives outside the pane so rows never remount on its re-renders;
 *  the region keys ('assigned' = shown, 'all' = hidden) are the PaneDnd group names; the hidden zone
 *  grows into the pane's slack so its hide-highlight reads even while nothing's hidden. Title's eye is
 *  inert (it never hides). */
function VisibilityGroups({
  shownIds,
  hiddenIds,
  hiddenSet,
  schema,
  nameFor,
  onToggle,
}: {
  shownIds: string[]
  hiddenIds: string[]
  hiddenSet: Set<string>
  schema: PropertyDefinition[]
  nameFor: (id: string) => string
  onToggle: (id: string, hidden: boolean) => void
}): React.JSX.Element {
  const { assignedRef, allRef, allHighlighted } = usePaneRegions()
  const eyeFor = (id: string): ReactNode =>
    id === RESERVED_PROPERTY_ID.title ? (
      <span className={s.eyeInert} aria-hidden>
        <Icon name="eye" size={s.ICON.eye} />
      </span>
    ) : (
      <EyeToggle
        hidden={hiddenSet.has(id)}
        name={nameFor(id)}
        onToggle={() => onToggle(id, hiddenSet.has(id))}
      />
    )
  return (
    <>
      <div data-group="assigned" ref={assignedRef}>
        {shownIds.map((id) => (
          <RowShell key={id} id={id}>
            <MenuItem className={flushTrailing} leading={rowIcon(id, schema)} trailing={eyeFor(id)}>
              {nameFor(id)}
            </MenuItem>
          </RowShell>
        ))}
      </div>
      {/* No heading — the ghost IS the shown/hidden boundary (Nathan's call). The zone grows into
          the pane's slack so the hide-highlight reads even while nothing's hidden. */}
      <div
        data-group="all"
        ref={allRef}
        className={cx(s.hiddenZone, allHighlighted && s.allHighlight)}
      >
        {hiddenIds.map((id) => (
          <RowShell key={id} id={id}>
            <MenuItem
              className={cx(flushTrailing, s.hiddenRow)}
              leading={rowIcon(id, schema)}
              trailing={eyeFor(id)}
            >
              {nameFor(id)}
            </MenuItem>
          </RowShell>
        ))}
      </div>
    </>
  )
}

/**
 * The visibility list — a view's shown/hidden split as ONE flat list, shared by the Visibility pane
 * and the table view's Layout leaf. Below the header the rows run in the view's column order (Title,
 * the context tiers, and the properties together), then the hidden rows ghosted after them. Title
 * rides the list as a draggable anchor but never hides (its eye is inert), so a column can be dragged
 * before it — the reason it's listed at all. Drags carry the drag language: into the shown zone lands
 * at a slot (drop line), into the hidden zone hides (area highlight, no line — the hidden order is
 * derived). Hiding only flags (`hidden_properties`), never moves: an eye-unhide restores the property
 * to its remembered view slot; only a drag-in chooses a new one. Writes go through `views:save` +
 * `load()`, so the live table behind the dropdown updates on the same beat. An optional `footer` (the
 * Layout leaf's icon toggles) pins below the list.
 */
export function VisibilityList({
  source,
  schema,
  view,
  onBack,
  footer,
  label = 'Settings',
  current,
  maxHeight,
}: {
  source: CollectionNode | SetNode
  schema: PropertyDefinition[]
  view: SavedView
  onBack: () => void
  footer?: ReactNode
  /** TopRow back-label + right-side breadcrumb — the Visibility pane reads `Settings · Visibility`,
   *  the ViewSettings Layout leaf reads `Views · Layout`. */
  label?: string
  current?: string
  /** Height ceiling override — the ViewSettings Layout leaf passes ViewSettings' own max. */
  maxHeight?: number
}): React.JSX.Element | null {
  const load = useSession((st) => st.load)
  const saveView = useSaveView(source, load)
  const tree = useSession((st) => st.tree)
  if (!tree) return null

  const shownIds = resolveColumns(view, schema).map((c) => c.id)
  const hiddenIds = hiddenListIds(view.hidden_properties, schema)
  const hiddenSet = new Set(view.hidden_properties)
  const nameFor = (id: string): string => columnLabel(id, schema, tree.labels)

  const save = async (patch: Partial<SavedView>): Promise<void> => {
    const res = await saveView({ ...view, ...patch })
    if (!res.ok) await window.nexus.showError(res.error)
  }
  // The positional kinds are the ONE placeInShown write — a shown reorder and a drag-in unhide
  // differ only in whether the hidden filter bites; the membership kind ('unassign') is a hide.
  const handleDrop = (drop: PaneDrop): void => {
    if (drop.kind === 'unassign') void save(hideShown(view, drop.propId))
    else if (drop.kind === 'reorder-assigned' || drop.kind === 'assign')
      void save(placeInShown(view, shownIds, shownIds, drop.propId, drop.toIndex))
  }

  const paneRows: PaneRow[] = [
    ...shownIds.map((id) => ({ id, group: 'assigned' as const })),
    ...hiddenIds.map((id) => ({ id, group: 'all' as const })),
  ]

  return (
    <MenuScrollFrame
      header={<MenuPaneTopRow label={label} current={current} onBack={onBack} />}
      footer={footer}
      maxHeight={maxHeight}
    >
      <PaneDnd rows={paneRows} labelFor={nameFor} onDrop={handleDrop} slot={hiddenPaneSlot}>
        <VisibilityGroups
          shownIds={shownIds}
          hiddenIds={hiddenIds}
          hiddenSet={hiddenSet}
          schema={schema}
          nameFor={nameFor}
          onToggle={(id, hidden) => void save(hidden ? unhide(view, id) : hideShown(view, id))}
        />
      </PaneDnd>
    </MenuScrollFrame>
  )
}

/** The Visibility pane (SettingsPane → Visibility) — the active view's visibility list, no footer. */
export function HiddenPane({
  source,
  schema,
  onBack,
}: {
  source: CollectionNode | SetNode
  schema: PropertyDefinition[]
  onBack: () => void
}): React.JSX.Element | null {
  const { view } = useActiveView(source, schema)
  return (
    <VisibilityList
      source={source}
      schema={schema}
      view={view}
      onBack={onBack}
      current="Visibility"
    />
  )
}
