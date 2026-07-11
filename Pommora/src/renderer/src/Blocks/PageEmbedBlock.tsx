import { useMemo } from 'react'
import type { PageBlockEntry } from '@shared/blocks'
import { PageEmbed } from '@renderer/Embeds/PageEmbed'
import { flattenPages, type ConnectionsApi } from '@renderer/MarkdownPM/connections'
import { useSession } from '@renderer/store'

// The tile-flavored consumer of the shared PageEmbed seam (G-11): resolves the
// entry's page_id against the live tree and renders the embed. A dead reference
// renders nothing and keeps its space (E-2) — the tile persists until removed.

export function PageEmbedBlock({
  entry,
  editing,
  onBeginEdit,
  connections
}: {
  entry: PageBlockEntry
  editing: boolean
  onBeginEdit: (tileId: string) => void
  connections?: ConnectionsApi
}): React.JSX.Element | null {
  const tree = useSession((s) => s.tree)
  const select = useSession((s) => s.select)

  const page = useMemo(
    () => (tree ? (flattenPages(tree).find((p) => p.id === entry.page_id) ?? null) : null),
    [tree, entry.page_id]
  )

  if (!page) return null // dead reference — inert, space holds (E-2)
  return (
    <PageEmbed
      path={page.path}
      title={page.title}
      editing={editing}
      onBeginEdit={() => onBeginEdit(entry.id)}
      onOpen={() => void select({ kind: 'page', id: page.id, path: page.path })}
      showBanner={entry.banner !== false}
      showTitle={entry.title !== false}
      connections={connections}
    />
  )
}
