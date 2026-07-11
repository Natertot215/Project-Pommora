import { useRef, useState } from 'react'
import type { MutableKind } from '@shared/mutate'
import { defaultEntityIcon, iconNameOr } from '@renderer/design-system/symbols'
import { IconPicker } from '@renderer/Components/IconPicker'
import { useSession } from '../../store'
import type { BannerOwner } from '../Scope'
import { DetailTitleHeader } from '../DetailTitleHeader'
import { EditableInput } from '../../Components/EditableInput'
import { AddBannerButton } from './AddBannerButton'
import { assetUrl } from '../../assetUrl'

export function Banner({ owner }: { owner: BannerOwner }): React.JSX.Element {
  const mutate = useSession((s) => s.mutate)
  const submitRename = useSession((s) => s.submitRename)
  const load = useSession((s) => s.load)
  const defaultIcons = useSession((s) => s.personalization.defaultIcons)
  const [iconPickerOpen, setIconPickerOpen] = useState(false)
  const [editingHome, setEditingHome] = useState(false)
  const iconRef = useRef<SVGSVGElement>(null)

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
  if (!owner.banner) {
    return (
      <div className={`banner-empty${homeClass}`}>
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
      className={`banner${homeClass}`}
      onContextMenu={(e) => {
        e.preventDefault()
        void openMenu()
      }}
    >
      <img className="banner-img" src={assetUrl(owner.banner)} alt="" />
      {owner.kind === 'homepage' ? (
        // The homepage gets NO icon (its name is the nexus itself); its title double-clicks to
        // rename the nexus. Right-click still falls through to the banner menu.
        <span className="banner-title">{homeTitle('banner-title-text')}</span>
      ) : (
        <div className="banner-title">
          <DetailTitleHeader
            title={owner.name}
            icon={iconNameOr(owner.icon, defaultEntityIcon(owner.kind, defaultIcons))}
            iconRef={iconRef}
            onRename={(newName) => submitRename(owner.path, owner.kind as MutableKind, newName)}
            requestMenu={() => window.nexus.titleMenu()}
            onEditIcon={() => setIconPickerOpen(true)}
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
