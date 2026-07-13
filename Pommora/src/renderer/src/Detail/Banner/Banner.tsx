import { useRef, useState } from 'react'
import type { MutableKind } from '@shared/mutate'
import { Icon, defaultEntityIcon, iconNameOr } from '@renderer/design-system/symbols'
import { IconPicker } from '@renderer/Components/IconPicker'
import { useSession } from '../../store'
import { isSurfaceKind, type BannerOwner } from '../Scope'
import { DetailTitleHeader } from '../DetailTitleHeader'
import { EditableInput } from '../../Components/EditableInput'
import { AddBannerButton } from './AddBannerButton'
import { assetUrl } from '../../assetUrl'

export function Banner({ owner }: { owner: BannerOwner }): React.JSX.Element {
  const mutate = useSession((s) => s.mutate)
  const submitRename = useSession((s) => s.submitRename)
  const load = useSession((s) => s.load)
  const defaultIcons = useSession((s) => s.personalization.defaultIcons)
  const nexus = useSession((s) => s.tree?.nexus)
  const [iconPickerOpen, setIconPickerOpen] = useState(false)
  const [editingHome, setEditingHome] = useState(false)
  const iconRef = useRef<SVGSVGElement>(null)

  const iconHidden = owner.headingIconHidden === true
  const toggleHeadingIcon = (): Promise<boolean> =>
    mutate({ op: 'setHeadingIconHidden', path: owner.path, kind: owner.kind, hidden: !iconHidden })
  // The homepage identity in the banner: its profile photo, else the chosen glyph, else the default house
  // glyph — always rendered so hide/show slides it in/out (the `is-hidden` class collapses it) rather
  // than popping. `banner-home-icon` carries the slide transition.
  const homeIcon = (): React.ReactNode => {
    const cls = iconHidden ? 'banner-home-icon is-hidden' : 'banner-home-icon'
    if (nexus?.profileImage) return <img className={cls} src={assetUrl(nexus.profileImage)} alt="" />
    return <Icon name={nexus?.profileIcon ?? 'house'} className={cls} />
  }
  const openHomeTitleMenu = async (e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    e.stopPropagation() // the homepage title menu, not the banner's Change/Remove-photo menu underneath
    // Rename (→ renameNexus, writes the root folder title) + Hide/Show Icon; no Change Icon (the nexus
    // icon is set from the settings pane / ribbon). Double-click also enters rename.
    const action = await window.nexus.titleMenu({ toggleIcon: true, iconHidden, noEditIcon: true })
    if (action === 'rename') setEditingHome(true)
    else if (action === 'toggleIcon') await toggleHeadingIcon()
  }

  // The homepage IS the nexus, so its title renames the root folder (renameNexus, a fs rename) — not
  // submitRename. Double-click the homepage title to edit it in place; this is the sole rename-nexus
  // affordance now that the sidebar's NexusHeader is gone.
  const commitHome = (next: string): void => {
    setEditingHome(false)
    if (!next || next === owner.name) return
    void window.nexus.renameNexus(next).then(async (res) => {
      if (!res.ok) await window.nexus.showError(res.error)
      else await load()
    })
  }
  const homeTitle = (className: string): React.ReactNode =>
    editingHome ? (
      <EditableInput value={owner.name} className={className} onCommit={commitHome} onCancel={() => setEditingHome(false)} />
    ) : (
      <span className={className} onDoubleClick={() => setEditingHome(true)} title="Double-click to rename">
        {owner.name}
      </span>
    )
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

  const homeClass = owner.kind === 'homepage' ? ' is-homepage' : ''
  const surfaceClass = isSurfaceKind(owner.kind) ? ' is-surface' : ''
  if (!owner.banner) {
    return (
      <div className={`banner-empty${homeClass}${surfaceClass}`}>
        <AddBannerButton onClick={() => void addOrChange()} />
        {owner.kind === 'homepage' ? (
          homeTitle('banner-empty-title')
        ) : (
          <div className="banner-empty-title">{owner.name}</div>
        )}
      </div>
    )
  }
  return (
    <div
      className={`banner${homeClass}${surfaceClass}`}
      onContextMenu={(e) => {
        e.preventDefault()
        void openMenu()
      }}
    >
      <img className="banner-img" src={assetUrl(owner.banner)} alt="" />
      {owner.kind === 'homepage' ? (
        // The homepage IS the nexus: its identity icon (photo/glyph) leads the title, hidden/shown from the
        // title's right-click; the title double-clicks to rename the nexus. Right-click the banner (not the
        // title) still falls through to the Change/Remove-photo menu.
        <span className="banner-title" onContextMenu={(e) => void openHomeTitleMenu(e)}>
          {homeIcon()}
          {homeTitle('banner-title-text')}
        </span>
      ) : (
        <div className="banner-title">
          <DetailTitleHeader
            title={owner.name}
            icon={iconNameOr(owner.icon, defaultEntityIcon(owner.kind, defaultIcons))}
            iconHidden={iconHidden}
            iconRef={iconRef}
            onRename={(newName) => submitRename(owner.path, owner.kind as MutableKind, newName)}
            requestMenu={() => window.nexus.titleMenu({ toggleIcon: true, iconHidden })}
            onEditIcon={() => setIconPickerOpen(true)}
            onToggleIcon={() => void toggleHeadingIcon()}
          />
        </div>
      )}
      <IconPicker
        open={iconPickerOpen}
        onClose={() => setIconPickerOpen(false)}
        triggerRef={iconRef}
        value={owner.icon}
        onSelect={(id) => void mutate({ op: 'setIcon', path: owner.path, kind: owner.kind as MutableKind, icon: id })}
      />
    </div>
  )
}
