import { useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { useSession } from '../store'
import { EditableInput } from '../Components/EditableInput'
import { PhotoCropModal } from '../Components/PhotoCropModal'
import * as s from './nexusHeader.css'

/**
 * The nexus header at the top of the sidebar (replaces the Homepage stub): a circular photo beside
 * the nexus title (its root folder name) over an optional description. Figma node 432:1919.
 * Right-click the photo → native "Add Photo" → image picker → circular crop → saved into `.nexus/`.
 * Double-click the title to rename the folder; double-click the description to set a 50-char blurb.
 */
export function NexusHeader({
  name,
  description,
  photo
}: {
  name: string
  description: string
  photo: string | null
}): React.JSX.Element {
  const load = useSession((st) => st.load)
  const mutate = useSession((st) => st.mutate)
  const select = useSession((st) => st.select)
  const selected = useSession((st) => st.selection.kind === 'homepage')
  const [cropImage, setCropImage] = useState<string | null>(null)
  const [editing, setEditing] = useState<'title' | 'description' | null>(null)

  const pickPhoto = (e: React.MouseEvent): void => {
    e.preventDefault()
    void window.nexus.photoMenu().then((picked) => {
      if (picked) setCropImage(picked)
    })
  }

  const saveCrop = async (dataUrl: string): Promise<void> => {
    const res = await window.nexus.saveNexusPhoto(dataUrl)
    setCropImage(null)
    if (!res.ok) await window.nexus.showError(res.error)
    else await load()
  }

  const commitTitle = (next: string): void => {
    setEditing(null)
    if (!next || next === name) return
    void window.nexus.renameNexus(next).then(async (res) => {
      if (!res.ok) await window.nexus.showError(res.error)
      else await load()
    })
  }

  const commitDescription = (next: string): void => {
    setEditing(null)
    if (next !== description) void mutate({ op: 'setNexusDescription', description: next })
  }

  return (
    <div
      className={selected ? `${s.header} ${s.headerSelected}` : s.header}
      onClick={() => void select({ kind: 'homepage' })}
    >
      <span className={photo ? s.photo : `${s.photo} ${s.photoEmpty}`} onContextMenu={pickPhoto} title="Right-click to add a photo">
        {photo ? <img className={s.photoImg} src={photo} alt="" /> : <Icon name="square-dashed" size={20} />}
      </span>
      <div className={s.textBlock}>
        {editing === 'title' ? (
          <EditableInput value={name} className={s.titleInput} onCommit={commitTitle} onCancel={() => setEditing(null)} />
        ) : (
          <span className={s.title} onDoubleClick={() => setEditing('title')} title="Double-click to rename">
            {name}
          </span>
        )}
        {editing === 'description' ? (
          <EditableInput value={description} className={s.descriptionInput} maxLength={50} onCommit={commitDescription} onCancel={() => setEditing(null)} />
        ) : (
          <span
            className={description ? s.description : s.descriptionEmpty}
            onDoubleClick={() => setEditing('description')}
            title="Double-click to edit description"
          >
            {description || 'Description'}
          </span>
        )}
      </div>
      {cropImage && <PhotoCropModal image={cropImage} onCancel={() => setCropImage(null)} onConfirm={saveCrop} />}
    </div>
  )
}
