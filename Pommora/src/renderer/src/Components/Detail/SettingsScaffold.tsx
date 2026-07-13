import { useRef, useState } from 'react'
import type { MutableKind } from '@shared/mutate'
import type { EntityIconKind } from '@shared/types'
import { useSession } from '../../store'
import { Icon, iconNameOr, defaultEntityIcon } from '../../design-system/symbols'
import { InteractionField } from '../../design-system/components/InteractionField'
import { MenuBottomRow, MenuScrollFrame } from '../../design-system/components/menu'
import { footerLockAction, lockIcon } from '../../Blocks/handleMenu.css'
import { findContext } from '../../Detail/Scope'
import { IconPicker } from '../IconPicker'
import { PhotoCropModal } from '../PhotoCropModal'
import { InlineEditHeader } from './InlineEditHeader'
import { useNexusIcon } from '../useNexusIcon'
import { assetUrl } from '../../assetUrl'
import * as s from './settingsPane.css'

/**
 * The stripped settings pane for identity surfaces (homepage, contexts) — an icon+title header with
 * none of SettingsPane's view-config leaves (Layout/Group/Filter/Sort are view concepts). The homepage
 * identity is the nexus itself (photo-or-glyph icon → the native icon menu) plus the board-lock footer
 * (G-3). A context is editable identity: its icon (→ the glyph picker) + title (inline rename), no lock.
 */
export function SettingsScaffold(): React.JSX.Element | null {
  const selection = useSession((st) => st.selection)
  const tree = useSession((st) => st.tree)
  const locked = useSession((st) => st.homepageLocked)
  const setLocked = useSession((st) => st.setHomepageLocked)
  const submitRename = useSession((st) => st.submitRename)
  const mutate = useSession((st) => st.mutate)
  const defaultIcons = useSession((st) => st.personalization.defaultIcons)
  const { profileImage, profileIcon, openMenu, cropImage, setCropImage, pickerOpen, setPickerOpen, confirmCrop, selectGlyph } =
    useNexusIcon()
  const iconRef = useRef<HTMLButtonElement>(null)
  const ctxIconRef = useRef<HTMLButtonElement>(null)
  const [ctxPickerOpen, setCtxPickerOpen] = useState(false)
  if (!tree) return null

  if (selection.kind === 'homepage') {
    const photoUrl = profileImage ? assetUrl(profileImage) : null
    return (
      <>
        <MenuScrollFrame
          footer={
            <MenuBottomRow
              leading={
                <button
                  type="button"
                  aria-label={locked ? 'Unlock board' : 'Lock board'}
                  className={footerLockAction}
                  onClick={() => void setLocked(!locked)}
                >
                  <Icon name="lock" size={12} className={lockIcon} />
                  {locked ? 'Unlock' : 'Lock'}
                </button>
              }
            />
          }
        >
          <div className={s.header}>
            <button
              ref={iconRef}
              type="button"
              className={s.iconButton}
              onClick={() => void openMenu()}
              aria-label="Change the nexus icon or photo"
            >
              {photoUrl ? <img className={s.headerPhotoImg} src={photoUrl} alt="" /> : <Icon name={profileIcon ?? 'square-dashed'} />}
            </button>
            <InteractionField className={s.titleField}>{tree.nexus.name}</InteractionField>
          </div>
        </MenuScrollFrame>
        <IconPicker open={pickerOpen} onClose={() => setPickerOpen(false)} triggerRef={iconRef} value={profileIcon} onSelect={selectGlyph} />
        {cropImage && <PhotoCropModal image={cropImage} onCancel={() => setCropImage(null)} onConfirm={confirmCrop} />}
      </>
    )
  }

  if (selection.kind === 'context') {
    const node = findContext(tree, selection.id)
    if (!node) return null
    return (
      <>
        <InlineEditHeader
          value={node.name}
          icon={iconNameOr(node.icon, defaultEntityIcon(node.kind as EntityIconKind, defaultIcons))}
          iconRef={ctxIconRef}
          onIconClick={() => setCtxPickerOpen(true)}
          onCommit={(next) => {
            if (next && next !== node.name) void submitRename(node.path, node.kind as MutableKind, next)
          }}
        />
        <IconPicker
          open={ctxPickerOpen}
          onClose={() => setCtxPickerOpen(false)}
          triggerRef={ctxIconRef}
          value={node.icon}
          onSelect={(id) => {
            setCtxPickerOpen(false)
            void mutate({ op: 'setIcon', path: node.path, kind: node.kind as MutableKind, icon: id })
          }}
        />
      </>
    )
  }
  return null
}
