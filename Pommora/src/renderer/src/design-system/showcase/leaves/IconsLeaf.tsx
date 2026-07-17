import { useState } from 'react'
import { Icon, icons, type IconName } from '@renderer/design-system/symbols'
import { SortableZone, useDragItem, reorder } from '@renderer/design-system/interactions/drag'
import { useIsCompact } from './helpers'

function IconCell({ name }: { name: IconName }): React.JSX.Element {
  const { setNodeRef, style, handle } = useDragItem(name)
  return (
    <div ref={setNodeRef} style={style} className="ds-icon-cell" title={name} {...handle}>
      <Icon name={name} size={20} />
      <span className="ds-icon-name">{name}</span>
    </div>
  )
}

/** Foundations · Icons — the registry, auto-iterated; drag to reorder (compact stays static
 *  so the page scrolls). */
export function IconsLeaf(): React.JSX.Element {
  const [names, setNames] = useState<IconName[]>(() => Object.keys(icons) as IconName[])
  const compact = useIsCompact()
  const cells = (
    <div className="ds-icon-grid">
      {names.map((n) =>
        compact ? (
          <div className="ds-icon-cell" key={n} title={n}>
            <Icon name={n} size={20} />
            <span className="ds-icon-name">{n}</span>
          </div>
        ) : (
          <IconCell key={n} name={n} />
        ),
      )}
    </div>
  )
  return (
    <div className="ds-leaf">
      <section className="ds-section">
        <h2>Icons · PommoraIcons ({names.length})</h2>
        {compact ? (
          cells
        ) : (
          <SortableZone
            items={names}
            layout="grid"
            getItemLabel={(id) => id}
            onReorder={(a, o) =>
              setNames((x) =>
                reorder(
                  x.map((id) => ({ id })),
                  a,
                  o,
                ).map(({ id }) => id),
              )
            }
          >
            {cells}
          </SortableZone>
        )}
      </section>
    </div>
  )
}
