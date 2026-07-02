import type { ColumnStyle } from '@shared/columnStyles'
import type { StatusGroupId } from '@shared/properties'
import type { ResolvedColumn, ViewRow } from '@shared/types'
import { chip, chipCapsule, chipCheckbox, chipColor } from '@renderer/design-system/tokens'
import { cx } from '@renderer/design-system/cx'
import { Icon, asIconName, type IconName } from '@renderer/design-system/symbols'
import { Switch } from '@renderer/design-system/components/Switches/Switch'
import { Chip } from '@renderer/Components/Chip'
import { ContextChip } from '@renderer/Components/ContextChip'
import { chipColorFor } from '@renderer/design-system/tokens/colorMap'
import { resolveFieldValue } from '../pipeline/value'
import { fileLabel, formatDate, formatNumber } from '../PropertyEditing/formatValue'
import { statusGroupOf } from '../PropertyEditing/statusCycle'
import { findOption } from './cellResolve'
import type { ResolveContext } from './resolveContext'

/** The fixed status group's glyph — shared by the capsule and checkbox looks (the checkbox
 *  renders upcoming as an empty square instead of the dashed circle). */
const GROUP_GLYPH: Record<StatusGroupId, IconName> = { upcoming: 'circle-dashed', in_progress: 'minus', done: 'check' }

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
  style
}: {
  row: ViewRow
  column: ResolvedColumn
  ctx: ResolveContext
  hideIcon: boolean
  style: ColumnStyle
}): React.JSX.Element | null {
  if (column.kind === 'title') {
    // The page's frontmatter icon, else the file-text default (the sidebar's page glyph) — so every page
    // reads with an icon (E-3). Hide Page Icons drops it entirely.
    const iconName = hideIcon ? undefined : (asIconName(row.icon) ?? 'file-text')
    return (
      <span className="cell-title">
        {iconName ? <Icon name={iconName} size={14} /> : null}
        <span className="cell-title-text">{row.title}</span>
      </span>
    )
  }

  const v = resolveFieldValue(row, column.id)
  switch (v.kind) {
    case 'select':
    case 'status': {
      const opt = findOption(column.id, v.value, ctx.schema)
      if (v.kind === 'status' && (style.look === 'capsule' || style.look === 'checkbox')) {
        const group = statusGroupOf(v.value, ctx.schema.find((d) => d.id === column.id))
        return style.look === 'capsule' ? (
          <span className={cx(chip, chipColor[chipColorFor(opt?.color)], chipCapsule)}>
            <Icon name={group ? GROUP_GLYPH[group] : 'circle-dashed'} size={13} />
          </span>
        ) : (
          <span className={cx(chip, chipColor[chipColorFor(opt?.color)], chipCheckbox)}>
            {group && group !== 'upcoming' ? <Icon name={GROUP_GLYPH[group]} size={12} strokeWidth={3} /> : null}
          </span>
        )
      }
      return <Chip color={chipColorFor(opt?.color)} label={opt?.label ?? v.value} />
    }
    case 'multiSelect':
      return (
        <span className="cell-chips">
          {v.value.map((val) => {
            const o = findOption(column.id, val, ctx.schema)
            return <Chip key={val} color={chipColorFor(o?.color)} label={o?.label ?? val} />
          })}
        </span>
      )
    case 'checkbox':
      if (style.look === 'switch') {
        // Read-only visual until the gesture pass wires the toggle write.
        return <Switch checked={v.value} onChange={() => {}} ariaLabel="Checkbox value" />
      }
      return (
        <span className={cx(chip, chipColor.default, chipCheckbox)}>
          {v.value ? <Icon name="check" size={12} strokeWidth={3} /> : null}
        </span>
      )
    case 'context':
      return (
        <span className="cell-chips">
          {v.value.map((id) => {
            const c = ctx.contextsById.get(id)
            return <ContextChip key={id} color={chipColorFor(c?.color)} title={c?.title ?? id} />
          })}
        </span>
      )
    case 'url':
      // The 'title' look shows the fetched page title once the fetch Prospect lands; until then
      // both looks render the URL in the link color. Opens through the sanctioned IPC — raw <a>
      // navigation is denied by main's will-navigate hardening.
      return v.value ? (
        <a
          className="cell-link"
          href={v.value}
          onClick={(e) => {
            e.preventDefault()
            e.stopPropagation()
            void window.nexus.openExternal(v.value)
          }}
        >
          {v.value}
        </a>
      ) : null
    case 'datetime':
      return (
        <span className="cell-muted">
          {formatDate(v.value, style.date_format ?? 'full', style.time_format ?? 'none')}
        </span>
      )
    case 'number':
      return <span>{formatNumber(v.value, style.number_format ?? 'decimal')}</span>
    case 'file':
      // Each chip opens its own file (A-9) — the click stays on the chip, not the cell/row.
      return (
        <span className="cell-chips">
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
        </span>
      )
    default:
      return null
  }
}
