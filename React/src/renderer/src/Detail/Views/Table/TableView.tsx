import { useEffect, useMemo, useState } from 'react'
import type { CollectionNode, NexusTree, ResolvedGroup, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import type { PageFrontmatter } from '@shared/schemas'
import type { PropertyValue } from '@shared/propertyValue'
import { type SavedView, mintDefaultView } from '@shared/views'
import { flattenContainer } from '../pipeline/group'
import { resolveView } from '../pipeline/resolveView'
import { resolveFieldValue } from '../pipeline/value'
import { useSession } from '../../../store'

/** A Collection uses its own schema; a Set inherits its ancestor Collection's (schema lives only on
 *  the Collection). [] when the owning Collection can't be found. */
function resolveContainerSchema(tree: NexusTree, source: CollectionNode | SetNode): PropertyDefinition[] {
  if (source.kind === 'collection') return source.properties ?? []
  const collections = [...tree.collections, ...tree.userSections.flatMap((s) => s.collections)]
  const owns = (sets: SetNode[] | undefined): boolean =>
    (sets ?? []).some((s) => s.id === source.id || owns(s.sets))
  return collections.find((c) => owns(c.sets))?.properties ?? []
}

/** The view to render: the per-machine active view if still present, else the first saved view, else
 *  a freshly-minted default (sentinel id until first saved). */
function pickView(source: CollectionNode | SetNode, activeId: string | undefined, schema: PropertyDefinition[]): SavedView {
  const views = source.views ?? []
  const active = activeId ? views.find((v) => v.id === activeId) : undefined
  return active ?? views[0] ?? mintDefaultView(schema)
}

/** Minimal cell text — proves the Part-1 pipeline carries live values end-to-end. Part 2 builds the
 *  real type-aware cells/chips off the same `resolveFieldValue` seam. */
function cellText(v: PropertyValue): string {
  switch (v.kind) {
    case 'select':
    case 'status':
    case 'url':
    case 'date':
    case 'datetime':
      return v.value
    case 'number':
      return String(v.value)
    case 'checkbox':
      return v.value ? '✓' : ''
    case 'multiSelect':
    case 'relation':
      return v.value.join(', ')
    case 'file':
      return v.value.map((f) => f.path).join(', ')
    default:
      return ''
  }
}

export function TableView({ source }: { source: CollectionNode | SetNode }): React.JSX.Element {
  const tree = useSession((s) => s.tree)
  const selection = useSession((s) => s.selection)
  const select = useSession((s) => s.select)
  const [values, setValues] = useState<Record<string, PageFrontmatter>>({})
  const [activeViewId, setActiveViewId] = useState<string | undefined>(undefined)

  // Lazy value load + active-view pointer on container open; `cancelled` guards a fast container swap.
  useEffect(() => {
    let cancelled = false
    void window.nexus.loadValues(source.path).then((v) => {
      if (!cancelled) setValues(v)
    })
    void window.nexus.activeViews.get().then((m) => {
      if (!cancelled) setActiveViewId(m[source.id])
    })
    return () => {
      cancelled = true
    }
  }, [source.path, source.id])

  const schema = useMemo(() => (tree ? resolveContainerSchema(tree, source) : []), [tree, source])
  const view = useMemo(() => pickView(source, activeViewId, schema), [source, activeViewId, schema])
  const { columns, groups } = useMemo(() => {
    const { rows, setTree } = flattenContainer(source, values)
    return resolveView({ rows, setTree, view, schema })
  }, [source, values, view, schema])

  const renderGroup = (g: ResolvedGroup, depth: number): React.JSX.Element => (
    <div key={g.key} className="view-group" data-depth={depth}>
      {g.kind !== 'ungrouped' ? <div className="group-header">{g.key}</div> : null}
      {g.items.length > 0 ? (
        <table className="data-table">
          <thead>
            <tr>
              {columns.map((c) => (
                <th key={c.id}>{c.id}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {g.items.map((row) => (
              <tr
                key={row.id}
                className={`data-row${selection.kind === 'page' && selection.id === row.id ? ' selected' : ''}`}
                onClick={() => void select({ kind: 'page', id: row.id, path: row.path })}
              >
                {columns.map((c) => (
                  <td key={c.id}>{cellText(resolveFieldValue(row, c.id))}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
      {g.children?.map((child) => renderGroup(child, depth + 1))}
    </div>
  )

  if (groups.length === 0) return <div className="table-empty">No pages here</div>
  return <div className="table-view">{groups.map((g) => renderGroup(g, 0))}</div>
}
