import { Icon } from '@renderer/design-system/symbols'
import { useSession } from '../../store'
import type { BannerOwner } from '../Scope'

/** URL for a stored nexus-relative asset path, served by the main-process nexus-asset:// protocol. */
const assetUrl = (rel: string): string => `nexus-asset://nexus/${encodeURI(rel)}`

/**
 * The shared image banner (Family A): a full-width cover behind the glass chrome at the top of a
 * view. No banner → a hover-revealed "Add Banner" button; with one → the image, the entity name
 * overlaid, and a native macOS Change / Remove menu. Mirrors Swift's ContainerBannerView; the
 * scaffold positions the two states (full-bleed image vs. in-body strip).
 */
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
