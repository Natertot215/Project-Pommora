import type { CollectionNode, SetNode } from '@shared/types'
import type { SavedView } from '@shared/views'
import { Icon } from '@renderer/design-system/symbols'
import { Switch } from '@renderer/design-system/components/Switches/Switch'
import { MenuItem, MenuSeparator } from '../../design-system/components/menu'
import { flushTrailing } from '../../design-system/components/menu/menu.css'
import { cx } from '../../design-system/cx'
import { useSession } from '../../store'
import { saveViewAdopting } from '../../Detail/Views/viewMint'
import { ICON, switchScale, toggleRow } from './settingsPane.css'

/**
 * The table view's Layout icon toggles — Column Icons (the type-icon in each column header) and Page
 * Icons (the leading icon on every page row). Shared by both Layout surfaces: the ViewSettings
 * full-door Layout leaf (below the visibility list) and the SettingsPane flat-door Layout (below the
 * type grid). Both persist per-view (inverted `hide_*` flags) through the shared adopt-only writer and
 * drive the table live — Page Icons the leading page glyph, Column Icons each header's type glyph.
 */
export function LayoutToggles({
  source,
  view
}: {
  source: CollectionNode | SetNode
  view: SavedView
}): React.JSX.Element {
  const load = useSession((st) => st.load)
  const write = (patch: Partial<SavedView>): void => void saveViewAdopting(source, { ...view, ...patch }, load)

  return (
    <>
      <MenuSeparator flush />
      <MenuItem
        className={cx(flushTrailing, toggleRow)}
        leading={<Icon name="columns-3-cog" size={ICON.rootEntry} />}
        trailing={
          <span className={switchScale}>
            <Switch
              checked={!(view.hide_column_icons ?? false)}
              onChange={(next) => write({ hide_column_icons: !next })}
              ariaLabel="Column Icons"
            />
          </span>
        }
      >
        Column Icons
      </MenuItem>
      <MenuItem
        className={cx(flushTrailing, toggleRow)}
        leading={<Icon name="file-text" size={ICON.rootEntry} />}
        trailing={
          <span className={switchScale}>
            <Switch
              checked={!(view.hide_page_icons ?? false)}
              onChange={(next) => write({ hide_page_icons: !next })}
              ariaLabel="Page Icons"
            />
          </span>
        }
      >
        Page Icons
      </MenuItem>
    </>
  )
}
