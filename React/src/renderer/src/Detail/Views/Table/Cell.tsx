import type { ColumnStyle } from '@shared/columnStyles'
import type { PropertyValue } from '@shared/propertyValue'
import type { ResolvedColumn, ViewRow } from '@shared/types'
import { chipBox, chipColor } from '@renderer/design-system/tokens'
import { cx } from '@renderer/design-system/cx'
import { Icon, asIconName, defaultEntityIcon } from '@renderer/design-system/symbols'
import { Switch } from '@renderer/design-system/components/Switches/Switch'
import { Chip, chipShapeForType } from '@renderer/Components/Chip'
import { ContextChip } from '@renderer/Components/ContextChip'
import { chipColorFor } from '@renderer/design-system/tokens/colorMap'
import { OverflowScroll } from '@renderer/design-system/components/OverflowScroll'
import { declaredType, resolveFieldValue } from '../pipeline/value'
import { fileLabel, formatDate, formatNumber } from '../PropertyEditing/formatValue'
import { statusGroupGlyph, statusGroupOf } from '../PropertyEditing/statusCycle'
import { StatusCapsule } from '../PropertyEditing/StatusCapsule'
import { findOption } from './cellResolve'
import { LinkCell } from './LinkCell'
import type { ResolveContext } from './resolveContext'

/** Type-aware cell render (Part 2 G-1/G-2): the title with its page icon; chips for select/status;
 *  several chips for multi-select; a checkbox glyph; ContextChips for tiers; an inline link for url;
 *  per-file chips; formatted date/number text. The per-view `style` picks each type's look + formats.
 *  Every value routes through the resolution context so no raw id ever shows; an empty/unknown value
 *  renders nothing. */
export function Cell({
  row,
  column,
  ctx,
  hideIcon,
  style,
  showFullLink,
  remove
}: {
  row: ViewRow
  column: ResolvedColumn
  ctx: ResolveContext
  hideIcon: boolean
  style: ColumnStyle
  /** While this cell's Rename popover is open, show the raw URL instead of the alias, so you can see
   *  what you're aliasing (a url cell only). */
  showFullLink?: boolean
  /** Commits the value that remains after a chip's hover × (null = the property clears entirely).
   *  Only PILL chips wire it — capsule/checkbox looks clear via their menu instead. */
  remove?: (next: PropertyValue | null) => void
}): React.JSX.Element | null {
  if (column.kind === 'title') {
    // The page's frontmatter icon, else the file-text default (the sidebar's page glyph) — so every page
    // reads with an icon (E-3). Hide Page Icons drops it entirely.
    const iconName = hideIcon ? undefined : (asIconName(row.icon) ?? defaultEntityIcon('page'))
    return (
      <OverflowScroll className="cell-title">
        {iconName ? <Icon name={iconName} size={14} /> : null}
        <span className="cell-title-text">{row.title}</span>
      </OverflowScroll>
    )
  }

  const v = resolveFieldValue(row, column.id, ctx.schema)

  // A checkbox column ALWAYS shows its box — even on a page with no stored value — so it toggles in
  // place without first assigning the property. The box keys off the column's schema TYPE, not the
  // value's presence; unchecked means no frontmatter value at all (the toggle strips the key).
  if (declaredType(column.id, ctx.schema) === 'checkbox') {
    const checked = v.kind === 'checkbox' && v.value
    return style.look === 'switch' ? (
      <Switch checked={checked} onChange={() => {}} ariaLabel="Checkbox value" />
    ) : (
      <span className={cx(chipBox, chipColor.default)}>
        {checked ? <Icon name="check" size={12} strokeWidth={3} /> : null}
      </span>
    )
  }

  switch (v.kind) {
    case 'select':
    case 'status': {
      const opt = findOption(column.id, v.value, ctx.schema)
      if (v.kind === 'status' && (style.look === 'capsule' || style.look === 'checkbox')) {
        const group = statusGroupOf(v.value, ctx.schema.find((d) => d.id === column.id))
        return style.look === 'capsule' ? (
          <StatusCapsule color={opt?.color} group={group} />
        ) : (
          <span className={cx(chipBox, chipColor[chipColorFor(opt?.color)])}>
            {group && group !== 'upcoming' ? <Icon name={statusGroupGlyph(group)} size={12} strokeWidth={3} /> : null}
          </span>
        )
      }
      return (
        <OverflowScroll className="cell-chips">
          <Chip
            color={chipColorFor(opt?.color)}
            label={opt?.label ?? v.value}
            shape={chipShapeForType(v.kind)}
            {...(remove ? { onRemove: () => remove(null) } : {})}
          />
        </OverflowScroll>
      )
    }
    case 'multiSelect':
      return (
        <OverflowScroll className="cell-chips">
          {v.value.map((val) => {
            const o = findOption(column.id, val, ctx.schema)
            return (
              <Chip
                key={val}
                color={chipColorFor(o?.color)}
                label={o?.label ?? val}
                shape={chipShapeForType(v.kind)}
                {...(remove ? { onRemove: () => remove({ kind: 'multiSelect', value: v.value.filter((x) => x !== val) }) } : {})}
              />
            )
          })}
        </OverflowScroll>
      )
    case 'context':
      return (
        <OverflowScroll className="cell-chips">
          {v.value.map((id) => {
            const c = ctx.contextsById.get(id)
            return (
              <ContextChip
                key={id}
                color={chipColorFor(c?.color)}
                title={c?.title ?? id}
                {...(remove ? { onRemove: () => remove({ kind: 'context', value: v.value.filter((x) => x !== id) }) } : {})}
              />
            )
          })}
        </OverflowScroll>
      )
    case 'url':
      // A bare URL or a markdown `[alias](url)`. LinkCell owns the render + its link-title fetch so the
      // store subscription stays off every other cell type. showFullLink pins the raw URL while renaming.
      return <LinkCell raw={v.value} def={ctx.schema.find((d) => d.id === column.id)} showFullLink={showFullLink} />

    case 'datetime':
      return (
        <OverflowScroll className="cell-text-scroll cell-muted">
          {formatDate(v.value, style.date_format ?? 'full', style.time_format ?? 'none')}
        </OverflowScroll>
      )
    case 'number':
      return <OverflowScroll className="cell-text-scroll">{formatNumber(v.value, style.number_format ?? 'decimal')}</OverflowScroll>
    case 'file':
      // Each chip opens its own file (A-9) — the click stays on the chip, not the cell/row.
      return (
        <OverflowScroll className="cell-chips">
          {v.value.map((f) => (
            <span
              key={f.path}
              onClick={(e) => {
                e.stopPropagation()
                void window.nexus.openFile(f.path)
              }}
            >
              <Chip color="default" label={fileLabel(f, style.look === 'path' ? 'path' : 'filename')} />
            </span>
          ))}
        </OverflowScroll>
      )
    default:
      return null
  }
}
