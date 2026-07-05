import { forwardRef } from 'react'
import { useSession } from '../store'
import { AddBannerButton } from '../Detail/Banner/AddBannerButton'
import { DetailTitleHeader } from '../Detail/DetailTitleHeader'
import { assetUrl } from '../assetUrl'

interface Props {
  path: string
  title: string
  cover?: string
  onRename: (newName: string) => void | Promise<boolean | void>
  onEditIcon: () => void
}

/**
 * The page editor's header: a full-bleed cover band (the Swift-compatible `cover`) with the title
 * overlaid bottom-left, or — with no cover — a hover Add-Banner strip above the title. The title is
 * the shared DetailTitleHeader (right-click → Rename / Edit Icon); the banner has its own
 * right-click → Change / Remove. Both menus are native + separate, never overlapping.
 */
export const PageHeader = forwardRef<HTMLDivElement, Props>(function PageHeader(
  { path, title, cover, onRename, onEditIcon },
  ref
) {
  const mutate = useSession((s) => s.mutate)
  const reloadPage = useSession((s) => s.reloadPage)

  const setBanner = async (dataUrl: string | null): Promise<void> => {
    if (await mutate({ op: 'setBanner', path, kind: 'page', dataUrl })) await reloadPage()
  }
  const addOrChange = async (): Promise<void> => {
    const dataUrl = await window.nexus.pickImage()
    if (dataUrl) await setBanner(dataUrl)
  }
  const bannerMenu = async (): Promise<void> => {
    const action = await window.nexus.bannerMenu()
    if (action === 'change') await addOrChange()
    else if (action === 'remove') await setBanner(null)
  }

  const titleHeader = (
    <DetailTitleHeader
      title={title}
      onRename={onRename}
      requestMenu={() => window.nexus.titleMenu()}
      onEditIcon={onEditIcon}
    />
  )

  return (
    <div className={`mdpm-header${cover ? ' has-banner' : ''}`} ref={ref}>
      {cover ? (
        <div
          className="mdpm-banner"
          onContextMenu={(e) => {
            e.preventDefault()
            void bannerMenu()
          }}
        >
          <img className="mdpm-banner-img" src={assetUrl(cover)} alt="" />
          <div className="mdpm-banner-overlay">{titleHeader}</div>
        </div>
      ) : (
        <>
          <AddBannerButton onClick={() => void addOrChange()} />
          {titleHeader}
          <div className="mdpm-divider" />
        </>
      )}
    </div>
  )
})
