import { useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { useSession } from '../store'
import { EditableInput } from '../Components/EditableInput'
import { PhotoCropModal } from '../Components/PhotoCropModal'
import * as s from './nexusHeader.css'
import { assetUrl } from '../assetUrl'

/**
 * The nexus header at the top of the sidebar: a circular profile photo beside the nexus title
 * (its root folder name) over an optional subtitle. Profile image + subtitle live in
 * `.nexus/settings.json` (Swift parity), served via nexus-asset://. Right-click the photo →
 * native picker → circular crop. Double-click the title to rename the folder; double-click the
 * subtitle to set a ≤30-char blurb.
 */
export function NexusHeader({
  name,
  profileImage,
  profileSubtitle
}: {
  name: string
  profileImage: string | null
  profileSubtitle: string
}): React.JSX.Element {
  const load = useSession((st) => st.load)
  const mutate = useSession((st) => st.mutate)
  const select = useSession((st) => st.select)
  const selected = useSession((st) => st.selection.kind === 'homepage')
  const [cropImage, setCropImage] = useState<string | null>(null)
  const [editing, setEditing] = useState<'title' | 'subtitle' | null>(null)

  const pickPhoto = (e: React.MouseEvent): void => {
    e.preventDefault()
    void window.nexus.photoMenu().then((picked) => {
      if (picked) setCropImage(picked)
    })
  }

  const saveCrop = async (dataUrl: string): Promise<void> => {
    setCropImage(null)
    await mutate({ op: 'setProfileImage', dataUrl }) // store.mutate refetches the tree
  }

  const commitTitle = (next: string): void => {
    setEditing(null)
    if (!next || next === name) return
    void window.nexus.renameNexus(next).then(async (res) => {
      if (!res.ok) await window.nexus.showError(res.error)
      else await load()
    })
  }

  const commitSubtitle = (next: string): void => {
    setEditing(null)
    if (next !== profileSubtitle) void mutate({ op: 'setProfileSubtitle', subtitle: next })
  }

  const photoUrl = profileImage ? assetUrl(profileImage) : null

  return (
    <div
      className={selected ? `${s.header} ${s.headerSelected}` : s.header}
      onClick={() => void select({ kind: 'homepage' })}
    >
      <span className={photoUrl ? s.photo : `${s.photo} ${s.photoEmpty}`} onContextMenu={pickPhoto} title="Right-click to add a photo">
        {photoUrl ? <img className={s.photoImg} src={photoUrl} alt="" /> : <Icon name="square-dashed" size={20} />}
      </span>
      <div className={s.textBlock}>
        {editing === 'title' ? (
          <EditableInput value={name} className={s.titleInput} onCommit={commitTitle} onCancel={() => setEditing(null)} />
        ) : (
          <span className={s.title} onDoubleClick={() => setEditing('title')} title="Double-click to rename">
            {name}
          </span>
        )}
        {editing === 'subtitle' ? (
          <EditableInput value={profileSubtitle} className={s.descriptionInput} maxLength={30} onCommit={commitSubtitle} onCancel={() => setEditing(null)} />
        ) : (
          <span
            className={profileSubtitle ? s.description : s.descriptionEmpty}
            onDoubleClick={() => setEditing('subtitle')}
            title="Double-click to edit subtitle"
          >
            {profileSubtitle || 'Subtitle'}
          </span>
        )}
      </div>
      {cropImage && <PhotoCropModal image={cropImage} onCancel={() => setCropImage(null)} onConfirm={saveCrop} />}
    </div>
  )
}
