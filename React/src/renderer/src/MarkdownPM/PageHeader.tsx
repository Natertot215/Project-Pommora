import { forwardRef } from 'react'
import type { IconName } from '@renderer/design-system/symbols'
import { useSession } from '../store'
import { DetailTitleHeader } from '../Detail/DetailTitleHeader'

const assetUrl = (rel: string): string => `nexus-asset://nexus/${encodeURI(rel)}`

interface Props {
  path: string
  title: string
  icon: IconName
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
  { path, title, icon, cover, onRename, onEditIcon },
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
      icon={icon}
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
          <div className="mdpm-add-banner">
            <button type="button" className="add-banner-btn" onClick={() => void addOrChange()} aria-label="Add banner">
              + Add Banner
            </button>
          </div>
          {titleHeader}
          <div className="mdpm-divider" />
        </>
      )}
    </div>
  )
})
