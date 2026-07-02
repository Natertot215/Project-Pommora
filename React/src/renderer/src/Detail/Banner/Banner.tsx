import type { BannerOwnerKind } from '@shared/mutate'
import { Icon, iconNameOr, type IconName } from '@renderer/design-system/symbols'
import { useSession } from '../../store'
import type { BannerOwner } from '../Scope'
import { AddBannerButton } from './AddBannerButton'

const assetUrl = (rel: string): string => `nexus-asset://nexus/${encodeURI(rel)}`

/** Per-kind fallback so a bannered view always carries a glyph (banner ⇒ icon, even the default);
 *  banner-less stays text-only. Pages never reach here — their header is title-only by design. */
const DEFAULT_ICON: Record<BannerOwnerKind, IconName> = {
  collection: 'gallery-vertical-end',
  set: 'folder-closed',
  area: 'layout-grid',
  topic: 'layout-grid',
  project: 'layout-grid',
  homepage: 'house',
  page: 'file-text'
}

export function Banner({ owner }: { owner: BannerOwner }): React.JSX.Element {
  const mutate = useSession((s) => s.mutate)
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
      <span className="banner-title">
        <Icon name={iconNameOr(owner.icon, DEFAULT_ICON[owner.kind])} className="banner-title-icon" />
        <span className="banner-title-text">{owner.name}</span>
      </span>
    </div>
  )
}
