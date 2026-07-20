import type { ReactNode } from 'react'
import type { CollectionNode, ResolvedGroup, SetNode } from '@shared/types'
import type { SavedView } from '@shared/views'
import { chipBox, chipColor, text } from '@renderer/design-system/tokens'
import { chipColorFor } from '@renderer/design-system/tokens/colorMap'
import { cx } from '@renderer/design-system/cx'
import {
  asRenderableIcon,
  defaultEntityIcon,
  Icon,
  iconNameOr,
} from '@renderer/design-system/symbols'
import { Reveal } from '@renderer/design-system/components/Reveal'
import { Chip, chipShapeForType } from '@renderer/Components/Chip'
import { RenamableTitle } from '@renderer/Components/RenamableTitle'
import { declaredType } from './pipeline/value'
import { findOption, groupLabel } from './Table/cellResolve'
import { checkboxBoxStyle } from './Table/checkboxLook'
import { formatBucketLabel } from './PropertyEditing/formatValue'
import type { ResolveContext } from './Table/resolveContext'
import './GroupBand.css'

/** The plain-text label + the rendered head visual for a group band — the single home for the five
 *  glyph cases the table and cards views both show. Structural Set → its icon + name (swapping to the
 *  shared inline rename input while the store renames its path, when `setPath` is given); status/select
 *  → a Chip (status a pill, select a squared label); checkbox → the box glyph + On/Off; datetime → the
 *  property icon + bucket label; ungrouped → the container's own icon + title; otherwise the raw value.
 *  Chip colour/shape resolve from the schema here, so `ResolvedGroup` stays colourless. */
export function resolveBandHead(
  group: ResolvedGroup,
  view: SavedView,
  ctx: ResolveContext,
  setNames: Map<string, string>,
  setIcons: Map<string, string | undefined>,
  source: CollectionNode | SetNode,
  setPath?: string,
): { label: string; glyph: ReactNode } {
  if (group.kind === 'ungrouped') {
    const label = source.title
    return {
      label,
      glyph: (
        <span className="group-name">
          <Icon
            name={iconNameOr(
              source.icon,
              defaultEntityIcon(source.kind === 'collection' ? 'collection' : 'set'),
            )}
            size={13}
          />
          {label}
        </span>
      ),
    }
  }
  if (group.kind === 'structural-set') {
    const title = setNames.get(group.key) ?? group.key
    return {
      label: title,
      glyph: (
        <span className="group-name">
          <Icon name={iconNameOr(setIcons.get(group.key), defaultEntityIcon('set'))} size={13} />
          {setPath ? (
            <RenamableTitle path={setPath} kind="set" title={title} className="band-title-input" />
          ) : (
            title
          )}
        </span>
      ),
    }
  }
  // A property band lives in two homes: top-level property grouping, or a sub-group bucket inside a
  // set band (its raw value rides `bucket`; `key` is the composite collapse id).
  const propId =
    view.group?.kind === 'property'
      ? view.group.property_id
      : view.group?.kind !== 'flat'
        ? view.sub_group?.property_id
        : undefined
  const label = groupLabel(group, view, ctx, setNames)
  if (!propId) return { label, glyph: <span className="group-name">{group.key}</span> }
  const value = group.bucket ?? group.key

  const groupType = declaredType(propId, ctx.schema)
  const def = ctx.schema.find((d) => d.id === propId)
  switch (groupType) {
    case 'status':
    case 'select': {
      const opt = findOption(propId, value, ctx.schema)
      return {
        label,
        glyph: (
          <Chip
            color={chipColorFor(opt?.color)}
            label={opt?.label ?? value}
            shape={chipShapeForType(groupType)}
          />
        ),
      }
    }
    case 'checkbox': {
      const on = value === 'true'
      const color = def?.checkbox_color
      return {
        label,
        glyph: (
          <span className="group-name">
            <span
              className={cx(chipBox, on ? undefined : chipColor.default)}
              style={checkboxBoxStyle(on, color)}
            >
              {on ? <Icon name="check" size={12} strokeWidth={3} /> : null}
            </span>
            {on ? 'On' : 'Off'}
          </span>
        ),
      }
    }
    case 'datetime': {
      const icon = asRenderableIcon(def?.icon)
      const style = view.column_styles?.[propId]
      const granularity =
        (view.group?.kind === 'property'
          ? view.group.date_granularity
          : view.sub_group?.date_granularity) ?? 'month'
      const dateLabel = formatBucketLabel(
        value,
        granularity,
        style?.date_format ?? 'full',
        view.date_separator ?? 'dash',
      )
      return {
        label,
        glyph: (
          <span className="group-name">
            {icon ? <Icon name={icon} size={13} /> : null}
            {dateLabel}
          </span>
        ),
      }
    }
    default:
      return { label, glyph: <span className="group-name">{value}</span> }
  }
}

/** The band-drag wiring a table group passes down (from `useBandDrag`): `ref` marks the measured head,
 *  `handle` arms the glyph as the drag surface, and the two flags drive the pick-up mute / nest tint. */
export interface BandDragHandle {
  ref: (el: HTMLElement | null) => void
  handle: { onPointerDown: (e: React.PointerEvent) => void }
  isDragging: boolean
  isNestTarget: boolean
}

/** The shared group-band chrome: the disclosure twisty, the resolved glyph (also the drag + click
 *  surface), an optional hover "+", and the band body inside a `Reveal`. Presentational — every
 *  view-specific behaviour arrives as props: the table injects `dragHandle`/`onOpen`/`onContextMenu`
 *  and its rows as children; cards omits them and passes its card grid. `headless` drops the head and
 *  forces the body open (cards' Group By: None band). The glyph's single-click toggles the disclosure,
 *  double-click opens an openable Set; the twisty + "+" isolate on pointerdown so they never arm a band
 *  gesture, and a double-click's two clicks net out on the disclosure. */
export function GroupBand({
  glyph,
  collapsed,
  onToggle,
  showAdd = false,
  headless = false,
  fill = false,
  indent,
  subBand = false,
  dragHandle,
  onOpen,
  onContextMenu,
  children,
}: {
  glyph: ReactNode
  collapsed: boolean
  onToggle: () => void
  showAdd?: boolean
  headless?: boolean
  fill?: boolean
  indent?: string
  subBand?: boolean
  dragHandle?: BandDragHandle
  onOpen?: () => void
  onContextMenu?: (e: React.MouseEvent) => void
  children: ReactNode
}): React.JSX.Element {
  const outsideRename = (e: React.MouseEvent): boolean =>
    !(e.target as HTMLElement).closest?.('input')
  return (
    <div className={cx('group-band', subBand && 'sub-band')}>
      {!headless && (
        // The band row carries the section rhythm + indent + zoom (table); the head inside carries the
        // sticky pin + drag — kept on separate elements so zoom never rides the sticky offset.
        <div className="group-band-row" style={indent ? { paddingLeft: indent } : undefined}>
          <div
            ref={dragHandle?.ref}
            className={cx(
              'group-band-head',
              text.body.emphasized,
              dragHandle?.isDragging && 'band-dragging',
              dragHandle?.isNestTarget && 'band-nest-target',
            )}
            onContextMenu={onContextMenu}
          >
            <button
              type="button"
              className="group-band-twisty"
              onClick={onToggle}
              onPointerDown={(e) => e.stopPropagation()}
              aria-label={collapsed ? 'Expand group' : 'Collapse group'}
            >
              <Icon name="chevron-right" size={12} className={cx('twisty', !collapsed && 'open')} />
            </button>
            <span
              className="group-band-glyph"
              {...(dragHandle?.handle ?? {})}
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
              {glyph}
            </span>
            {showAdd ? (
              <button
                type="button"
                className="group-band-add"
                tabIndex={-1}
                onPointerDown={(e) => e.stopPropagation()}
                aria-label="New page in group"
              >
                <Icon name="plus" size={13} />
              </button>
            ) : null}
          </div>
        </div>
      )}
      <Reveal open={headless || !collapsed} fill={fill}>
        {children}
      </Reveal>
    </div>
  )
}
