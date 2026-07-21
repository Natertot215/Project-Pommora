import type { CollectionNode, SetNode } from '@shared/types'
import type { CardBanner, SavedView } from '@shared/views'
import { Icon } from '@renderer/design-system/symbols'
import { Switch } from '@renderer/design-system/components/Switches/Switch'
import { MenuItem, MenuSeparator } from '../../design-system/components/menu'
import { flushTrailing } from '../../design-system/components/menu/menu.css'
import { cx } from '../../design-system/cx'
import { useSession } from '../../store'
import { useSaveView } from '@renderer/Embeds/ViewEmbedScope'
import { PickerControl, type PickerChoice } from './PickerControl'
import { ICON, switchScale, toggleRow } from './settingsPane.css'

const BANNERS: PickerChoice<CardBanner>[] = [
  { value: 'cover', label: 'Cover' },
  { value: 'preview', label: 'Preview' },
  { value: 'none', label: 'None' },
]

/**
 * The cards view's options — Card Banner (the card image source) and the Hide Location / Wrap
 * Titles / Hide Icons / Set Cards switches; Card Style + Scale live in the ViewSettings footing.
 * Shared by both Layout surfaces: the full door's Layout leaf and the SettingsPane flat door. All
 * persist per-view through the shared adopt-only writer.
 */
export function CardsOptions({
  source,
  view,
}: {
  source: CollectionNode | SetNode
  view: SavedView
}): React.JSX.Element {
  const load = useSession((st) => st.load)
  const saveView = useSaveView(source, load)
  const write = (patch: Partial<SavedView>): void => void saveView({ ...view, ...patch })

  return (
    <>
      <MenuSeparator flush />
      <MenuItem
        className={cx(flushTrailing, toggleRow)}
        leading={<Icon name="image" size={ICON.rootEntry} />}
        trailing={
          <PickerControl
            ariaLabel="Card Banner"
            value={view.card_banner ?? 'cover'}
            options={BANNERS}
            onPick={(v) => write({ card_banner: v })}
            solid
          />
        }
      >
        Card Banner
      </MenuItem>
      <MenuItem
        className={cx(flushTrailing, toggleRow)}
        leading={<Icon name="map" size={ICON.rootEntry} />}
        trailing={
          <span className={switchScale}>
            <Switch
              checked={view.hide_location ?? false}
              onChange={(next) => write({ hide_location: next })}
              ariaLabel="Hide Location"
            />
          </span>
        }
      >
        Hide Location
      </MenuItem>
      <MenuItem
        className={cx(flushTrailing, toggleRow)}
        leading={<Icon name="wrap-text" size={ICON.rootEntry} />}
        trailing={
          <span className={switchScale}>
            <Switch
              checked={view.wrap_titles ?? false}
              onChange={(next) => write({ wrap_titles: next })}
              ariaLabel="Wrap Titles"
            />
          </span>
        }
      >
        Wrap Titles
      </MenuItem>
      <MenuItem
        className={cx(flushTrailing, toggleRow)}
        leading={<Icon name="eye-off" size={ICON.rootEntry} />}
        trailing={
          <span className={switchScale}>
            <Switch
              checked={view.hide_page_icons ?? false}
              onChange={(next) => write({ hide_page_icons: next })}
              ariaLabel="Hide Icons"
            />
          </span>
        }
      >
        Hide Icons
      </MenuItem>
      <MenuItem
        className={cx(flushTrailing, toggleRow)}
        leading={<Icon name="folder-closed" size={ICON.rootEntry} />}
        trailing={
          <span className={switchScale}>
            <Switch
              checked={view.set_cards ?? true}
              onChange={(next) => write({ set_cards: next })}
              ariaLabel="Set Cards"
            />
          </span>
        }
      >
        Set Cards
      </MenuItem>
    </>
  )
}
