import { useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { useSession } from '../store'
import { PhotoCropModal } from '../Components/PhotoCropModal'
import { assetUrl } from '../assetUrl'
import * as s from './nexusHeader.css'

/**
 * The nexus profile photo as the Homepage ribbon icon — the circular avatar (or dashed-square
 * fallback), sized to the ribbon. Right-click opens the native Add/Change Photo menu → crop. Its
 * click (homepage select) is owned by the ribbon button that wraps it. Rename-nexus now lives on
 * the homepage banner title, not here.
 */
export function NexusPhoto({ size }: { size: number }): React.JSX.Element {
  const profileImage = useSession((st) => st.tree?.nexus.profileImage ?? null)
  const mutate = useSession((st) => st.mutate)
  const [cropImage, setCropImage] = useState<string | null>(null)

  const pickPhoto = (e: React.MouseEvent): void => {
    e.preventDefault()
    void window.nexus.photoMenu().then((picked) => {
      if (picked) setCropImage(picked)
    })
  }
  const saveCrop = async (dataUrl: string): Promise<void> => {
    setCropImage(null)
    await mutate({ op: 'setProfileImage', dataUrl })
  }

  const photoUrl = profileImage ? assetUrl(profileImage) : null
  const dim = { width: size, height: size }
  return (
    <>
      <span
        className={photoUrl ? s.photo : `${s.photo} ${s.photoEmpty}`}
        style={dim}
        onContextMenu={pickPhoto}
        title="Right-click to add a photo"
      >
        {photoUrl ? <img className={s.photoImg} src={photoUrl} alt="" /> : <Icon name="square-dashed" size={Math.round(size * 0.6)} />}
      </span>
      {cropImage && <PhotoCropModal image={cropImage} onCancel={() => setCropImage(null)} onConfirm={saveCrop} />}
    </>
  )
}
