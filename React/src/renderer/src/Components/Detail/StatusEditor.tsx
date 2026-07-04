import { chipColorFor } from '@renderer/design-system/tokens/colorMap'
import type { StatusGroup } from '@shared/properties'
import { Chip } from '../Chip'
import * as s from './viewPane.css'

/**
 * The Status option editor (Planning 7-3) — the option list grouped by status group (Open / Active /
 * Done): each group's heading + its option chips, a chip defaulting to its group's colour when it
 * carries none of its own. Reuses the Select / Multi OptionEditor's chip + row treatment; the
 * per-group +, rename, recolour, reorder, and cross-group drag land in later slices.
 */
export function StatusEditor({ groups }: { groups: StatusGroup[] }): React.JSX.Element {
  return (
    <div className={s.statusGroups}>
      {groups.map((g) => (
        <div key={g.id} className={s.statusGroup}>
          <div className={s.optionsRow}>
            <span className={s.optionsLabel}>{g.label}</span>
          </div>
          <div className={s.optionList}>
            {g.options.map((o) => (
              <div key={o.value} className={s.optionRow}>
                <Chip shape="label" color={chipColorFor(o.color ?? g.color)} label={o.label} />
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}
