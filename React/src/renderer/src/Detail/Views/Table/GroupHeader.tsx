import type { ReactNode } from 'react'
import type { ResolvedGroup } from '@shared/types'
import type { SavedView } from '@shared/views'
import { chip, chipCheckbox, chipColor, text } from '@renderer/design-system/tokens'
import { cx } from '@renderer/design-system/cx'
import { Icon, asIconName } from '@renderer/design-system/symbols'
import { Chip } from '@renderer/Components/Chip'
import { chipColorFor } from '@renderer/design-system/tokens/colorMap'
import { declaredType } from '../pipeline/value'
import { useBandDrag } from './bandDnd'
import { findOption } from './cellResolve'
import type { ResolveContext } from './resolveContext'

/** The glyph for a group header. Structural Set → its name; status/select → a Chip (status is always a
 *  pill per L-1, select per L-4); checkbox → the box glyph + On/Off (L-2); date → the property icon +
 *  bucket label (L-3); otherwise the raw key. */
function groupGlyph(
  group: ResolvedGroup,
  view: SavedView,
  ctx: ResolveContext,
  setNames: Map<string, string>,
  setIcons: Map<string, string | undefined>
): ReactNode {
  // Structural Set/folder group (E-3): the Set's own icon (or the folder default), immune to Hide Page
  // Icons — it names the container, not a page — then the Set title.
  if (group.kind === 'structural-set') {
    return (
      <span className="group-name">
        <Icon name={asIconName(setIcons.get(group.key)) ?? 'folder-closed'} size={13} />
        {setNames.get(group.key) ?? group.key}
      </span>
    )
  }
  const propId = view.group?.kind === 'property' ? view.group.property_id : undefined
  if (!propId) return <span className="group-name">{group.key}</span>

  switch (declaredType(propId, ctx.schema)) {
    case 'status':
    case 'select': {
      const opt = findOption(propId, group.key, ctx.schema)
      return <Chip color={chipColorFor(opt?.color)} label={opt?.label ?? group.key} />
    }
    case 'checkbox': {
      const on = group.key === 'true'
      return (
        <span className="group-name">
          <span className={cx(chip, chipColor.default, chipCheckbox)}>
            {on ? <Icon name="check" size={12} strokeWidth={3} /> : null}
          </span>
          {on ? 'On' : 'Off'}
        </span>
      )
    }
    case 'datetime': {
      const icon = asIconName(ctx.schema.find((d) => d.id === propId)?.icon)
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

/** A Set / property group header: the sidebar's chevron-twisty (reused, rotates on `--disclosure`), the
 *  resolved glyph — the band-drag surface (C-6) — and a hover-revealed "+" to add a page to this group
 *  (Part 2 E-4 / L). The twisty + "+" isolate on POINTERDOWN so they can never arm a band gesture. */
export function GroupHeader({
  group,
  view,
  ctx,
  setNames,
  setIcons,
  collapsed,
  onToggle
}: {
  group: ResolvedGroup
  view: SavedView
  ctx: ResolveContext
  setNames: Map<string, string>
  setIcons: Map<string, string | undefined>
  collapsed: boolean
  onToggle: () => void
}): React.JSX.Element {
  const { ref, handle, isDragging, isNestTarget } = useBandDrag(group.key)
  return (
    <span
      ref={ref}
      className={cx('group-header', text.body.emphasized, isDragging && 'band-dragging', isNestTarget && 'band-nest-target')}
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
      <span className="band-glyph" {...handle}>
        {groupGlyph(group, view, ctx, setNames, setIcons)}
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
