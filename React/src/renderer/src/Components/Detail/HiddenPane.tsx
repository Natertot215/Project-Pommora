import { useEffect, useState, type ReactNode } from 'react'
import type { CollectionNode, SetNode } from '@shared/types'
import { type PropertyDefinition, RESERVED_PROPERTY_ID } from '@shared/properties'
import { DEFAULT_VIEW_ID, type SavedView } from '@shared/views'
import { Icon } from '@renderer/design-system/symbols'
import { useSession } from '../../store'
import { MenuItem, MenuSeparator, MenuTopRow } from '../../design-system/components/menu'
import { flushTrailing } from '../../design-system/components/menu/menu.css'
import { resolveColumns } from '../../Detail/Views/pipeline/columns'
import { columnLabel } from '../../Detail/Views/Table/columnLabel'
import { pickView } from '../../Detail/Views/Table/TableView'
import { PaneDnd, RowShell, usePaneRegions } from './paneDnd'
import type { PaneDrop, PaneRow } from './paneDndModel'
import {
  CONTEXT_TIERS,
  hiddenListIds,
  hiddenPaneSlot,
  hideShown,
  placeInShown,
  shownPropertyIds,
  unhide
} from './hiddenPaneModel'
import { PropertyTypeIcon } from './PropertyTypes'
import { cx } from '../../design-system/cx'
import * as s from './viewPane.css'

/** A row's leading glyph: schema props wear their type icon; tiers wear the context type's;
 *  Modified falls back with its type meta. */
function rowIcon(id: string, schema: PropertyDefinition[]): ReactNode {
  const def = schema.find((d) => d.id === id)
  if (def) return <PropertyTypeIcon type={def.type} size={s.ICON.doc} />
  if (id === RESERVED_PROPERTY_ID.modifiedAt) return <PropertyTypeIcon type="last_edited_time" size={s.ICON.doc} />
  return <PropertyTypeIcon type="context" size={s.ICON.doc} />
}

/** The eye toggle — rest shows the current state's glyph, hover previews the toggle: a hidden
 *  row runs the same pair in reverse (Nathan's spec). Both glyphs mount; CSS swaps them. */
function EyeToggle({ hidden, name, onToggle }: { hidden: boolean; name: string; onToggle: () => void }): React.JSX.Element {
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

/** The pane's three sections — contexts (static; rows ghost in place when hidden), the shown
 *  properties (the one drag region), and the hidden block. Lives outside HiddenPane so rows never
 *  remount on its re-renders; the region keys ('assigned' = properties, 'all' = hidden) are the
 *  PaneDnd group names; the hidden zone grows into the pane's slack so its hide-highlight reads
 *  even while nothing's hidden. */
function VisibilityGroups({
  shownIds,
  hiddenIds,
  hiddenSet,
  schema,
  nameFor,
  onToggle
}: {
  shownIds: string[]
  hiddenIds: string[]
  hiddenSet: Set<string>
  schema: PropertyDefinition[]
  nameFor: (id: string) => string
  onToggle: (id: string, hidden: boolean) => void
}): React.JSX.Element {
  const { assignedRef, allRef, allHighlighted } = usePaneRegions()
  const eye = (id: string): ReactNode => (
    <EyeToggle hidden={hiddenSet.has(id)} name={nameFor(id)} onToggle={() => onToggle(id, hiddenSet.has(id))} />
  )
  return (
    <>
      {CONTEXT_TIERS.map((id) => (
        <MenuItem
          key={id}
          className={cx(flushTrailing, hiddenSet.has(id) && s.hiddenRow)}
          leading={rowIcon(id, schema)}
          trailing={eye(id)}
        >
          {nameFor(id)}
        </MenuItem>
      ))}
      <MenuSeparator flush />
      <div data-group="assigned" ref={assignedRef}>
        {shownIds.map((id) => (
          <RowShell key={id} id={id}>
            <MenuItem className={flushTrailing} leading={rowIcon(id, schema)} trailing={eye(id)}>
              {nameFor(id)}
            </MenuItem>
          </RowShell>
        ))}
      </div>
      {/* No heading — the ghost IS the shown/hidden boundary (Nathan's call). The zone grows into
          the pane's slack so the hide-highlight reads even while nothing's hidden. */}
      <div data-group="all" ref={allRef} className={cx(s.hiddenZone, allHighlighted && s.allHighlight)}>
        {hiddenIds.map((id) => (
          <RowShell key={id} id={id}>
            <MenuItem className={cx(flushTrailing, s.hiddenRow)} leading={rowIcon(id, schema)} trailing={eye(id)}>
              {nameFor(id)}
            </MenuItem>
          </RowShell>
        ))}
      </div>
    </>
  )
}

/**
 * The Visibility pane — the active view's shown/hidden split. Contexts sit on top as a static
 * block: fixed Areas · Topics · Projects order, eye-only, ghosting in place when hidden (they
 * never join the hidden zone). Below the divider the properties run as ONE list, no heading: the
 * shown rows in view order, then the hidden rows ghosted after them in collection order. Drags
 * carry the drag language — into the shown zone lands at a slot (drop line; the gallery case:
 * card properties have no draggable columns), into the hidden zone hides (area highlight, no
 * line — the hidden order is derived). Every row's eye toggles its side. Hiding only flags
 * (`hidden_properties`), never moves: an eye-unhide restores the property to its remembered view
 * slot; only a drag-in chooses a new one. Writes go through `views:save` + `load()`, so the live
 * table behind the dropdown updates on the same beat.
 */
export function HiddenPane({
  source,
  schema,
  onBack
}: {
  source: CollectionNode | SetNode
  schema: PropertyDefinition[]
  onBack: () => void
}): React.JSX.Element | null {
  const load = useSession((st) => st.load)
  const tree = useSession((st) => st.tree)
  const [activeViewId, setActiveViewId] = useState<string | undefined>(undefined)
  useEffect(() => {
    let cancelled = false
    void window.nexus.activeViews.get().then((m) => {
      if (!cancelled) setActiveViewId(m[source.id])
    })
    return () => {
      cancelled = true
    }
  }, [source.id])
  if (!tree) return null

  const view = pickView(source, activeViewId, schema)
  const fullVisibleIds = resolveColumns(view, schema).map((c) => c.id)
  const shownIds = shownPropertyIds(fullVisibleIds)
  const hiddenIds = hiddenListIds(view.hidden_properties, schema)
  const hiddenSet = new Set(view.hidden_properties)
  const nameFor = (id: string): string => columnLabel(id, schema, tree.labels)

  const save = async (patch: Partial<SavedView>): Promise<void> => {
    // A view-less container renders the minted sentinel default; saveView swaps it for a real id
    // on EVERY save that still carries the sentinel. Adopt the returned id as the active view so a
    // second surface (the table behind) can't mint a rival default from its own stale sentinel
    // (breaker H-1); a subsequent save then updates in place instead of spawning another view.
    const wasSentinel = view.id === DEFAULT_VIEW_ID
    const res = await window.nexus.views.save(source.path, source.kind, { ...view, ...patch })
    if (!res.ok) {
      await window.nexus.showError(res.error)
      return
    }
    if (wasSentinel) {
      await window.nexus.activeViews.set(source.id, res.id)
      setActiveViewId(res.id)
    }
    await load()
  }
  // The positional kinds are the ONE placeInShown write — a shown reorder and a drag-in unhide
  // differ only in whether the hidden filter bites; the membership kind ('unassign') is a hide.
  const handleDrop = (drop: PaneDrop): void => {
    if (drop.kind === 'unassign') void save(hideShown(view, drop.propId))
    else if (drop.kind === 'reorder-assigned' || drop.kind === 'assign')
      void save(placeInShown(view, fullVisibleIds, shownIds, drop.propId, drop.toIndex))
  }

  const paneRows: PaneRow[] = [
    ...shownIds.map((id) => ({ id, group: 'assigned' as const })),
    ...hiddenIds.map((id) => ({ id, group: 'all' as const }))
  ]

  return (
    <PaneDnd rows={paneRows} labelFor={nameFor} onDrop={handleDrop} slot={hiddenPaneSlot}>
      <MenuTopRow label="Settings" onClick={onBack} className={s.topRowPad} />
      <MenuSeparator flush className={s.paneSeparator} />
      <VisibilityGroups
        shownIds={shownIds}
        hiddenIds={hiddenIds}
        hiddenSet={hiddenSet}
        schema={schema}
        nameFor={nameFor}
        onToggle={(id, hidden) => void save(hidden ? unhide(view, id) : hideShown(view, id))}
      />
    </PaneDnd>
  )
}
