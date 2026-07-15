import { Fragment } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens'
import { OverflowScroll } from '@renderer/design-system/components/OverflowScroll'
import type { NavTarget } from '@shared/types'
import type { ResolvedNav } from './navResolve'
import './navList.css'

// The stub row list both NavPane + NavMenu render: (icon)(title) … (path). Title takes the slack and
// eclipse-scrolls under the path when long; the path is right-aligned, grows left to a max, then
// eclipse-scrolls itself — both via the shared OverflowScroll. The Figma gallery replaces this.
export function NavList({
  items,
  extras,
  onSelect
}: {
  items: ResolvedNav[]
  /** Unresolvable hits (agenda kinds) — listed inert until Agenda routing ships. */
  extras?: { key: string; title: string; kind: string }[]
  onSelect: (target: NavTarget) => void
}): React.JSX.Element | null {
  if (items.length === 0 && !extras?.length) return null
  return (
    <ul className="nav-list">
      {items.map((it) => (
        <li key={it.key} className="nav-item">
          <button type="button" className="nav-item-main" onClick={() => onSelect(it.target)}>
            <Icon name={it.icon} size={15} className="nav-item-lead" />
            <OverflowScroll className="nav-item-title">{it.title}</OverflowScroll>
            {it.path.length > 0 && (
              <OverflowScroll className={cx('nav-item-path', text.caption.standard)}>
                {it.path.map((crumb, i) => (
                  <Fragment key={i}>
                    {i > 0 && <span className="nav-path-sep">›</span>}
                    <Icon name={crumb.icon} size={12} className="nav-path-icon" />
                    <span className="nav-path-name">{crumb.title}</span>
                  </Fragment>
                ))}
              </OverflowScroll>
            )}
          </button>
        </li>
      ))}
      {extras?.map((e) => (
        <li key={e.key} className="nav-item nav-item-inert" title="Agenda navigation isn't wired yet">
          <span className="nav-item-title">{e.title}</span>
          <span className={cx('nav-item-path', text.caption.standard)}>{e.kind}</span>
        </li>
      ))}
    </ul>
  )
}
