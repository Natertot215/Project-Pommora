import { Icon } from '@renderer/design-system/symbols'
import { useSession } from '../../store'
import type { BannerOwner } from '../Scope'

const assetUrl = (rel: string): string => `nexus-asset://nexus/${encodeURI(rel)}`

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
        <div className="add-banner-strip">
          <button
            type="button"
            className="add-banner-btn"
            onClick={() => void addOrChange()}
            aria-label="Add banner"
            title="Add a banner"
          >
            <Icon name="square-plus" size={14} />
            Add Banner
          </button>
        </div>
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
      <span className="banner-title">{owner.name}</span>
    </div>
  )
}
