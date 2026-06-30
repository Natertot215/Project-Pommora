import { useEffect, useMemo, useState } from 'react'
import type { CollectionNode, NexusTree, ResolvedGroup, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import type { PageFrontmatter } from '@shared/schemas'
import { type SavedView, mintDefaultView } from '@shared/views'
import { flattenContainer } from '../pipeline/group'
import { resolveView } from '../pipeline/resolveView'
import { useSession } from '../../../store'
import { buildResolveContext } from './resolveContext'
import { buildSetNames, cellText, groupLabel } from './cellResolve'
import { columnLabel } from './columnLabel'
import { clampWidth, widthFor } from './columnWidths'

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
  const ctx = useMemo(() => (tree ? buildResolveContext(tree, schema) : null), [tree, schema])
  const setNames = useMemo(() => buildSetNames(source), [source])

  if (!ctx) return <div className="table-empty">Loading…</div>
  if (groups.length === 0) return <div className="table-empty">No pages here</div>

  // Saved widths are clamped to the type's [min, max] (Q-4) — a stale/out-of-range saved value can't
  // squash a column below legibility or stretch it past its cap.
  const colWidth = (id: string): number => clampWidth(view.column_widths?.[id] ?? widthFor(id, schema).default, id, schema)
  const totalWidth = columns.reduce((sum, c) => sum + colWidth(c.id), 0)
  // Per-layer indent on the title cell + group headers (J-3), DRY via the --table-indent / pad-x vars.
  const indent = (depth: number): string | undefined =>
    depth > 0 ? `calc(var(--table-pad-x) + var(--table-indent) * ${depth})` : undefined

  const renderRows = (g: ResolvedGroup, depth: number): React.JSX.Element[] => {
    const out: React.JSX.Element[] = []
    const label = groupLabel(g, view, ctx, setNames)
    if (label) {
      out.push(
        <tr key={`gh-${g.key}`} className="group-header-row">
          <td colSpan={columns.length} style={{ paddingLeft: indent(depth) }}>
            {label}
          </td>
        </tr>
      )
    }
    for (const row of g.items) {
      const sel = selection.kind === 'page' && selection.id === row.id
      out.push(
        <tr
          key={row.id}
          className={`data-row${sel ? ' selected' : ''}`}
          onClick={() => void select({ kind: 'page', id: row.id, path: row.path })}
        >
          {columns.map((c, i) => (
            <td key={c.id} style={i === 0 ? { paddingLeft: indent(depth) } : undefined}>
              {cellText(row, c.id, ctx)}
            </td>
          ))}
        </tr>
      )
    }
    for (const child of g.children ?? []) out.push(...renderRows(child, depth + 1))
    return out
  }

  return (
    <div className="table-view">
      <table className={`data-table${view.hide_borders ? ' no-borders' : ''}`} style={{ width: totalWidth }}>
        <colgroup>
          {columns.map((c) => (
            <col key={c.id} style={{ width: colWidth(c.id) }} />
          ))}
        </colgroup>
        <thead>
          <tr>
            {columns.map((c) => (
              <th key={c.id}>{columnLabel(c.id, schema, ctx.labels)}</th>
            ))}
          </tr>
        </thead>
        <tbody>{groups.flatMap((g) => renderRows(g, 0))}</tbody>
      </table>
    </div>
  )
}
