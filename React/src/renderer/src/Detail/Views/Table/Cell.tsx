import type { ResolvedColumn, ViewRow } from '@shared/types'
import { chip, chipCheckbox, chipColor } from '@renderer/design-system/tokens'
import { cx } from '@renderer/design-system/cx'
import { Icon, asIconName } from '@renderer/design-system/symbols'
import { Chip } from '@renderer/Components/Chip'
import { ContextChip } from '@renderer/Components/ContextChip'
import { chipColorFor } from '@renderer/design-system/tokens/chipColorMap'
import { resolveFieldValue } from '../pipeline/value'
import { findOption } from './cellResolve'
import type { ResolveContext } from './resolveContext'

function formatDate(iso: string): string {
  const d = new Date(iso)
  return Number.isNaN(d.getTime())
    ? iso
    : d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })
}

/** Type-aware cell render (Part 2 G-1/G-2): the title with its page icon; chips for select/status;
 *  several chips for multi-select; a checkbox glyph; ContextChips for tiers; an inline link for url; a
 *  date stub; plain text for number/file. Every value routes through the resolution context so no raw
 *  id ever shows; an empty/unknown value renders nothing. */
export function Cell({
  row,
  column,
  ctx,
  hideIcon
}: {
  row: ViewRow
  column: ResolvedColumn
  ctx: ResolveContext
  hideIcon: boolean
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
      return v.value ? (
        <a className="cell-link" href={v.value} onClick={(e) => e.stopPropagation()}>
          {v.value}
        </a>
      ) : null
    case 'datetime':
      return <span className="cell-muted">{formatDate(v.value)}</span>
    case 'number':
      return <span>{v.value}</span>
    case 'file':
      return <span>{v.value.map((f) => f.path.split('/').pop() ?? f.path).join(', ')}</span>
    default:
      return null
  }
}
