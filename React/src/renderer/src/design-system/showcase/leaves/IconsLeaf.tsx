import { Icon, icons } from '@renderer/design-system/symbols'

/** Foundations · Icons — the PommoraIcons registry (Tabler default + Lucide keeps + customs),
 *  auto-iterated. A static reference grid (reordering dozens of icons reads as noise, not a demo). */
export function IconsLeaf(): React.JSX.Element {
  const iconNames = Object.keys(icons) as Array<keyof typeof icons>
  return (
    <div className="ds-leaf">
      <section className="ds-section">
        <h2>Icons · PommoraIcons ({iconNames.length})</h2>
        <div className="ds-icon-grid">
          {iconNames.map((n) => (
            <div className="ds-icon-cell" key={n} title={n}>
              <Icon name={n} size={20} />
              <span className="ds-icon-name">{n}</span>
            </div>
          ))}
        </div>
      </section>
    </div>
  )
}
