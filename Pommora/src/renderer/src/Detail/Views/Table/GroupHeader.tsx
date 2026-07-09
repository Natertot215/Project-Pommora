import type { ReactNode } from 'react'
import type { ResolvedGroup } from '@shared/types'
import type { SavedView } from '@shared/views'
import { chipBox, chipColor, text } from '@renderer/design-system/tokens'
import { cx } from '@renderer/design-system/cx'
import { Icon, asRenderableIcon, defaultEntityIcon, iconNameOr } from '@renderer/design-system/symbols'
import { Chip, chipShapeForType } from '@renderer/Components/Chip'
import { chipColorFor } from '@renderer/design-system/tokens/colorMap'
import { declaredType } from '../pipeline/value'
import { RenamableTitle } from '@renderer/Components/RenamableTitle'
import { useBandDrag } from './bandDnd'
import { checkboxBoxStyle } from './checkboxLook'
import { findOption } from './cellResolve'
import type { ResolveContext } from './resolveContext'

/** The glyph for a group header. Structural Set → its name (swapping to the shared inline rename
 *  input while the store renames its path); status/select → a Chip (status is always a pill per
 *  L-1, select per L-4); checkbox → the box glyph + On/Off (L-2); date → the property icon +
 *  bucket label (L-3); otherwise the raw key. */
function groupGlyph(
  group: ResolvedGroup,
  view: SavedView,
  ctx: ResolveContext,
  setNames: Map<string, string>,
  setIcons: Map<string, string | undefined>,
  setPath: string | undefined
): ReactNode {
  // Structural Set/folder group (E-3): the Set's own icon (or the folder default), immune to Hide Page
  // Icons — it names the container, not a page — then the Set title.
  if (group.kind === 'structural-set') {
    const title = setNames.get(group.key) ?? group.key
    return (
      <span className="group-name">
        <Icon name={iconNameOr(setIcons.get(group.key), defaultEntityIcon('set'))} size={13} />
        {setPath ? <RenamableTitle path={setPath} kind="set" title={title} className="band-title-input" /> : title}
      </span>
    )
  }
  const propId = view.group?.kind === 'property' ? view.group.property_id : undefined
  if (!propId) return <span className="group-name">{group.key}</span>

  const groupType = declaredType(propId, ctx.schema)
  switch (groupType) {
    case 'status':
    case 'select': {
      const opt = findOption(propId, group.key, ctx.schema)
      return <Chip color={chipColorFor(opt?.color)} label={opt?.label ?? group.key} shape={chipShapeForType(groupType)} />
    }
    case 'checkbox': {
      const on = group.key === 'true'
      const color = ctx.schema.find((d) => d.id === propId)?.checkbox_color
      return (
        <span className="group-name">
          <span className={cx(chipBox, on ? undefined : chipColor.default)} style={checkboxBoxStyle(on, color)}>
            {on ? <Icon name="check" size={12} strokeWidth={3} /> : null}
          </span>
          {on ? 'On' : 'Off'}
        </span>
      )
    }
    case 'datetime': {
      const icon = asRenderableIcon(ctx.schema.find((d) => d.id === propId)?.icon)
      return (
        <span className="group-name">
          {icon ? <Icon name={icon} size={13} /> : null}
          {group.key}
        </span>
      )
    }
    default:
      return <span className="group-name">{group.key}</span>
  }
}

/** A Set / property group header on the sidebar's interaction model: the chevron-twisty (reused,
 *  rotates on `--disclosure`), the resolved glyph — the band-drag surface (C-6) AND the click
 *  surface (single-click toggles the disclosure, double-click opens an openable Set, right-click
 *  pops the native Set menu — New Page · Rename · …) — and a hover-revealed "+" to add a page to
 *  this group (Part 2 E-4 / L). The twisty + "+" isolate on POINTERDOWN so they can never arm a
 *  band gesture; a double-click's two clicks toggle-and-untoggle, so the disclosure nets out. */
export function GroupHeader({
  group,
  view,
  ctx,
  setNames,
  setIcons,
  setPath,
  onOpen,
  collapsed,
  onToggle
}: {
  group: ResolvedGroup
  view: SavedView
  ctx: ResolveContext
  setNames: Map<string, string>
  setIcons: Map<string, string | undefined>
  /** The structural Set's real path — enables the native menu + inline rename (undefined for
   *  property bands). */
  setPath?: string
  /** Present only for OPENABLE Sets (a Collection's direct children — sub-Sets are expand-only,
   *  matching the sidebar's selectable rule). */
  onOpen?: () => void
  collapsed: boolean
  onToggle: () => void
}): React.JSX.Element {
  const { ref, handle, isDragging, isNestTarget } = useBandDrag(group.key)
  const outsideRename = (e: React.MouseEvent): boolean => !(e.target as HTMLElement).closest?.('input')
  return (
    <span
      ref={ref}
      className={cx('group-header', text.body.emphasized, isDragging && 'band-dragging', isNestTarget && 'band-nest-target')}
      onContextMenu={
        setPath
          ? (e) => {
              e.preventDefault()
              e.stopPropagation()
              void window.nexus.contextMenu({ kind: 'set', path: setPath, title: setNames.get(group.key) ?? group.key })
            }
          : undefined
      }
    >
      <button
        type="button"
        className="group-twisty"
        onClick={onToggle}
        onPointerDown={(e) => e.stopPropagation()}
        aria-label={collapsed ? 'Expand group' : 'Collapse group'}
      >
        <Icon name="chevron-right" size={12} className={cx('twisty', !collapsed && 'open')} />
      </button>
      <span
        className="band-glyph"
        {...handle}
        onClick={(e) => {
          if (outsideRename(e)) onToggle()
        }}
        onDoubleClick={
          onOpen
            ? (e) => {
                if (outsideRename(e)) onOpen()
              }
            : undefined
        }
      >
        {groupGlyph(group, view, ctx, setNames, setIcons, setPath)}
      </span>
      {/* Hover-revealed: adds a page to this group, sorted to the group bottom (newItemsTo, default
          'bottom'). The caller is pending Nathan's creation-affordance design (Q-7/Q-9) — inert for now. */}
      <button
        type="button"
        className="group-add"
        tabIndex={-1}
        onPointerDown={(e) => e.stopPropagation()}
        aria-label="New page in group"
      >
        <Icon name="plus" size={13} />
      </button>
    </span>
  )
}
