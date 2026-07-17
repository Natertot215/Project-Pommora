import type { MutableKind } from '@shared/mutate'
import { useSession } from '../store'
import { EditableInput } from './EditableInput'

/** An entity's title that swaps to the store-driven inline rename input while this entity is
 *  being renamed (`store.renamingPath === path` — set by the native context menu's Rename via
 *  `begin-rename`). Commit runs the rename mutate through the store; unchanged/empty cancels.
 *  One flow for every renamable surface — sidebar rows and table group bands share it. */
export function RenamableTitle({
  path,
  kind,
  title,
  className,
}: {
  path: string
  kind: MutableKind
  title: string
  className: string
}): React.JSX.Element {
  const renamingPath = useSession((s) => s.renamingPath)
  const cancelRename = useSession((s) => s.cancelRename)
  const submitRename = useSession((s) => s.submitRename)
  if (renamingPath !== path) return <>{title}</>
  return (
    <EditableInput
      value={title}
      className={className}
      onCommit={(next) => {
        if (next && next !== title) void submitRename(path, kind, next)
        else cancelRename()
      }}
      onCancel={cancelRename}
    />
  )
}
