import { useState } from 'react'
import type { BannerOwnerKind, MutableKind } from '@shared/mutate'
import { iconNameOr, type IconName } from '@renderer/design-system/symbols'
import { IconPicker } from '@renderer/Components/IconPicker'
import { useSession } from '../../store'
import type { BannerOwner } from '../Scope'
import { DetailTitleHeader } from '../DetailTitleHeader'
import { AddBannerButton } from './AddBannerButton'
import { assetUrl } from '../../assetUrl'

/** Per-kind fallback so a bannered view always carries a glyph (banner ⇒ icon, even the default);
 *  banner-less stays text-only. Pages never reach here (their header is title-only by design) and
 *  the homepage shows no icon at all — Nathan's call. */
const DEFAULT_ICON: Record<Exclude<BannerOwnerKind, 'homepage'>, IconName> = {
  collection: 'gallery-vertical-end',
  set: 'folder-closed',
  area: 'layout-grid',
  topic: 'layout-grid',
  project: 'layout-grid',
  page: 'file-text'
}

export function Banner({ owner }: { owner: BannerOwner }): React.JSX.Element {
  const mutate = useSession((s) => s.mutate)
  const submitRename = useSession((s) => s.submitRename)
  const [iconPickerOpen, setIconPickerOpen] = useState(false)
  const setBanner = (dataUrl: string | null): Promise<boolean> =>
    mutate({ op: 'setBanner', path: owner.path, kind: owner.kind, dataUrl })

  const addOrChange = async (): Promise<void> => {
    const dataUrl = await window.nexus.pickImage()
    if (dataUrl) await setBanner(dataUrl)
  }
  const openMenu = async (): Promise<void> => {
    const action = await window.nexus.bannerMenu()
    if (action === 'change') await addOrChange()
    else if (action === 'remove') await setBanner(null)
  }

  if (!owner.banner) {
    return (
      <div className="banner-empty">
        <AddBannerButton onClick={() => void addOrChange()} />
        <div className="banner-empty-title">{owner.name}</div>
      </div>
    )
  }
  return (
    <div
      className="banner"
      onContextMenu={(e) => {
        e.preventDefault()
        void openMenu()
      }}
    >
      <img className="banner-img" src={assetUrl(owner.banner)} alt="" />
      {owner.kind === 'homepage' ? (
        // The homepage isn't a MutableKind (its name is the nexus itself) and gets NO icon — its
        // title stays inert and bare; right-click falls through to the banner menu.
        <span className="banner-title">
          <span className="banner-title-text">{owner.name}</span>
        </span>
      ) : (
        <div className="banner-title">
          <DetailTitleHeader
            title={owner.name}
            icon={iconNameOr(owner.icon, DEFAULT_ICON[owner.kind])}
            onRename={(newName) => submitRename(owner.path, owner.kind as MutableKind, newName)}
            requestMenu={() => window.nexus.titleMenu()}
            onEditIcon={() => setIconPickerOpen(true)}
          />
        </div>
      )}
      <IconPicker open={iconPickerOpen} onClose={() => setIconPickerOpen(false)} />
    </div>
  )
}
