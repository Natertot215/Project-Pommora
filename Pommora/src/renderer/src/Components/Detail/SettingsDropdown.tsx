import { useSession } from '../../store'
import { viewSettingsScope } from '../../Detail/ViewSettingsScope'
import { MenuSurface } from '../../design-system/components/menu'
import { SettingsPane } from './SettingsPane'
import { SettingsScaffold } from './SettingsScaffold'
import * as s from './settingsPane.css'

/**
 * The Settings dropdown — the glass shell behind the toolbar Settings button, openable on ANY view.
 * It owns the anchor + glass MenuSurface and is generic chrome: it derives a ViewSettingsScope from
 * the current selection and switches on it to pick the pane. A Collection/Set ('view') shows the
 * SettingsPane; the homepage shows the identity SettingsScaffold; other surfaces get a placeholder until
 * their own panes land. The button never binds to a specific pane — the content view's scope decides.
 */
export function SettingsDropdown({
  closing = false,
  notchInsetRight,
}: {
  closing?: boolean
  /** Beak aim, forwarded to the glass shell — from the pane's right edge to the Settings button. */
  notchInsetRight?: number
}): React.JSX.Element {
  const selection = useSession((st) => st.selection)
  const scope = viewSettingsScope(selection)
  return (
    <div className={s.anchor}>
      <MenuSurface closing={closing} notchInsetRight={notchInsetRight}>
        {scope === 'view' ? (
          <SettingsPane />
        ) : scope === 'homepage' || scope === 'context' ? (
          <SettingsScaffold />
        ) : (
          <div style={{ minHeight: 24 }} />
        )}
      </MenuSurface>
    </div>
  )
}
