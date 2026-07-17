import { useState } from 'react'
import { useSession } from '../store'

/**
 * The nexus identity icon (photo OR glyph) — the shared state + native-menu dispatch behind both the
 * sidebar ribbon avatar and the homepage SettingsPane header. The menu offers Change Icon (→ the glyph
 * picker), Add/Change Photo (→ the native image pick → crop → setProfileImage), and the removes. A photo
 * outranks a glyph in display; a glyph outranks the default placeholder.
 */
export function useNexusIcon() {
  const profileImage = useSession((st) => st.tree?.nexus.profileImage ?? null)
  const profileIcon = useSession((st) => st.tree?.nexus.profileIcon)
  const mutate = useSession((st) => st.mutate)
  const [cropImage, setCropImage] = useState<string | null>(null)
  const [pickerOpen, setPickerOpen] = useState(false)

  const openMenu = async (): Promise<void> => {
    const action = await window.nexus.iconMenu({
      hasPhoto: !!profileImage,
      hasGlyph: !!profileIcon,
    })
    if (action === 'changeIcon') setPickerOpen(true)
    else if (action === 'addPhoto') {
      const dataUrl = await window.nexus.pickImage()
      if (dataUrl) setCropImage(dataUrl)
    } else if (action === 'removePhoto') await mutate({ op: 'setProfileImage', dataUrl: null })
    else if (action === 'removeIcon') await mutate({ op: 'setProfileIcon', icon: null })
  }

  const confirmCrop = async (dataUrl: string): Promise<void> => {
    setCropImage(null)
    await mutate({ op: 'setProfileImage', dataUrl })
  }
  // Picking a glyph makes it the identity — so a photo (which outranks it in display) is cleared,
  // matching the "either a glyph or a photo" model: the chosen glyph shows immediately.
  const selectGlyph = (id: string): void => {
    setPickerOpen(false)
    void (async () => {
      await mutate({ op: 'setProfileIcon', icon: id })
      if (profileImage) await mutate({ op: 'setProfileImage', dataUrl: null })
    })()
  }

  return {
    profileImage,
    profileIcon,
    openMenu,
    cropImage,
    setCropImage,
    pickerOpen,
    setPickerOpen,
    confirmCrop,
    selectGlyph,
  }
}
