import { useEffect, useMemo, useRef, useState } from 'react'
import type { PropertyDefinition } from '@shared/properties'
import type { PropertyValue } from '@shared/propertyValue'
import { applyPropertyValue } from '@shared/propertyValue'
import type { PageFrontmatter } from '@shared/schemas'
import type { NexusTree, ResolvedColumn, ViewRow } from '@shared/types'
import { cx } from '@renderer/design-system/cx'
import { asRenderableIcon, defaultEntityIcon, Icon } from '@renderer/design-system/symbols'
import { propertyTypeIconName } from '../Components/Detail/PropertyTypes'
import { text } from '@renderer/design-system/tokens'
import { CalendarPicker } from '@renderer/design-system/components/CalendarPicker/CalendarPicker'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu/PickerMenu'
import { MenuItem } from '@renderer/design-system/components/menu'
import { Cell } from '../Detail/Views/Table/Cell'
import { buildContextsById, type ResolveContext } from '../Detail/Views/Table/resolveContext'
import { contextOptionsFor } from '../Detail/Views/pipeline/contextOptions'
import { TIER_LEVEL_BY_ID } from '../Detail/Views/Table/columnLabel'
import { PropertyEditor } from '../Detail/Views/PropertyEditing/PropertyEditor'
import { PropertyPicker } from '../Detail/Views/PropertyEditing/PropertyPicker'
import { formatDate } from '../Detail/Views/PropertyEditing/formatValue'
import { resolveFieldValue } from '../Detail/Views/pipeline/value'
import { NavCrumbs } from '../Navigation/NavList'
import { buildResolveIndex, resolveWith } from '../Navigation/navResolve'
import { isValidLink } from '@shared/links'
import { RESERVED_PROPERTY_ID } from '@shared/properties'
import { useSession, type PreviewTarget } from '../store'

// The front-matter inspector (G-1/I-13/I-14): the preview page's title, banner, context tiers, and
// schema properties — listed and editable through the SAME primitives the table views edit with
// (Cell render, PropertyPicker/CalendarPicker portals, the inline PropertyEditor). Writes go through
// mutate with the table's optimistic-patch pattern; the D-6 reconcile re-paths the open tab on rename.

/** The page's owning Collection by path prefix — schema lives only on Collections. */
const schemaForPage = (tree: NexusTree | null, path: string): PropertyDefinition[] => {
  if (!tree) return []
  const all = [...tree.collections, ...tree.userSections.flatMap((s) => s.collections)]
  return all.find((c) => path.startsWith(`${c.path}/`))?.properties ?? []
}

type Editing = { id: string; mode: 'picker' | 'editor' | 'date' } | null

export function PreviewInspector({ target }: { target: PreviewTarget }): React.JSX.Element {
  const tree = useSession((s) => s.tree)
  const mutate = useSession((s) => s.mutate)
  const [fm, setFm] = useState<PageFrontmatter | null>(null)
  const [title, setTitle] = useState('')
  const [editing, setEditing] = useState<Editing>(null)
  const triggerRef = useRef<HTMLElement | null>(null)
  // Empty properties hide from the field; + Add Property reveals one and opens its editor.
  const [revealed, setRevealed] = useState<ReadonlySet<string>>(new Set())
  const [addOpen, setAddOpen] = useState(false)
  const addRef = useRef<HTMLButtonElement | null>(null)
  // Right-click a property row → the remove menu (un-assigns: the key deletes from frontmatter).
  const [rowMenu, setRowMenu] = useState<{ id: string; x: number; y: number } | null>(null)
  const rowMenuRef = useRef<HTMLSpanElement | null>(null)

  useEffect(() => {
    let live = true
    setFm(null)
    setEditing(null)
    void window.nexus.openPage(target.path).then((r) => {
      if (!live || !r.ok) return
      setFm(r.page.frontmatter as PageFrontmatter)
      setTitle(r.page.title)
    })
    return () => {
      live = false
    }
  }, [target.path])

  const schema = useMemo(() => schemaForPage(tree, target.path), [tree, target.path])
  // The subfield's location breadcrumb — the container chain + the page itself as the last crumb.
  const location = useMemo(() => {
    if (!tree) return []
    const res = resolveWith(buildResolveIndex(tree), {
      kind: 'page',
      id: target.id,
      path: target.path,
    })
    return res ? [...res.path, { icon: res.icon, title: res.title }] : []
  }, [tree, target])
  const ctx = useMemo<ResolveContext | null>(
    () => (tree ? { schema, contextsById: buildContextsById(tree), labels: tree.labels } : null),
    [tree, schema],
  )
  const row = useMemo<ViewRow | null>(
    () => (fm ? { id: target.id, title, icon: fm.icon, path: target.path, frontmatter: fm } : null),
    [fm, title, target],
  )

  // Properties are ASSIGNED (Nathan's model): a row shows when its key exists in the page's
  // frontmatter OR was assigned this session via + Add Property — an assigned-but-empty row is
  // valid and stays. Unassigned properties live behind the Add picker.
  const isAssigned = (id: string): boolean => revealed.has(id) || fm?.properties?.[id] !== undefined

  const closeEditing = (): void => setEditing(null)

  const commitValue = (propertyId: string, value: PropertyValue | null): void => {
    setFm((prev) =>
      prev ? { ...prev, properties: applyPropertyValue(prev.properties, propertyId, value) } : prev,
    )
    void mutate({ op: 'setProperty', path: target.path, propertyId, value })
  }
  const commitTier = (tierId: string, ids: string[]): void => {
    const tier = TIER_LEVEL_BY_ID[tierId]
    setFm((prev) => (prev ? ({ ...prev, [`tier${tier}`]: ids } as PageFrontmatter) : prev))
    void mutate({ op: 'setTier', path: target.path, tier, contextIds: ids })
  }

  const editRow = (def: PropertyDefinition, el: HTMLElement): void => {
    triggerRef.current = el
    if (def.type === 'checkbox') {
      const v = row ? resolveFieldValue(row, def.id, schema) : { kind: 'null' as const }
      commitValue(def.id, {
        kind: 'checkbox',
        value: !(v.kind === 'checkbox' && v.value),
      })
      return
    }
    if (def.type === 'datetime') setEditing({ id: def.id, mode: 'date' })
    else if (def.type === 'number' || def.type === 'url') setEditing({ id: def.id, mode: 'editor' })
    else if (def.type === 'file' || def.type === 'last_edited_time') return
    else setEditing({ id: def.id, mode: 'picker' })
  }

  if (!ctx || !row || !fm) return <div className="pgpreview-insp" />

  const editingDef =
    editing &&
    (schema.find((d) => d.id === editing.id) ??
      (TIER_LEVEL_BY_ID[editing.id]
        ? { id: editing.id, name: '', type: 'context' as const }
        : undefined))
  const TIER_ENTITY: Record<string, 'area' | 'topic' | 'project'> = {
    [RESERVED_PROPERTY_ID.tier1]: 'area',
    [RESERVED_PROPERTY_ID.tier2]: 'topic',
    [RESERVED_PROPERTY_ID.tier3]: 'project',
  }
  const tierRows: Array<{ id: string; label: string }> = [
    { id: RESERVED_PROPERTY_ID.tier1, label: ctx.labels.area.plural },
    { id: RESERVED_PROPERTY_ID.tier2, label: ctx.labels.topic.plural },
    { id: RESERVED_PROPERTY_ID.tier3, label: ctx.labels.project.plural },
  ]

  return (
    <div className="pgpreview-insp">
      <div className="pgpreview-insp-rows edge-fade">
        {/* The Swift layout: two rounded fill fields — contexts, then properties. Empty
            properties hide; + Add Property reveals one through its own picker. */}
        {[
          tierRows.map((t) => ({ def: null, ...t })),
          schema.filter((d) => isAssigned(d.id)).map((d) => ({ def: d, id: d.id, label: d.name })),
        ].map((group, gi) => (
          <div key={gi === 0 ? 'contexts' : 'properties'} className="pgpreview-insp-group">
            {group.map(({ def, id, label }) => {
        const col: ResolvedColumn = { id, kind: def ? 'property' : 'tier' }
        return (
          <div
            key={id}
            className="pgpreview-insp-row"
            data-insp-id={id}
            onContextMenu={
              def
                ? (e) => {
                    e.preventDefault()
                    setRowMenu({ id, x: e.clientX, y: e.clientY })
                  }
                : undefined
            }
          >
            <span className={cx('pgpreview-insp-label', text.caption.standard)}>
              <Icon
                name={
                  def
                    ? (asRenderableIcon(def.icon) ?? propertyTypeIconName(def.type) ?? 'tag')
                    : defaultEntityIcon(TIER_ENTITY[id] ?? 'area')
                }
                size={12}
              />
              {label}
            </span>
            {/* biome-ignore lint/a11y/useKeyWithClickEvents: pointer-first edit entry, like cells */}
            <span
              className="pgpreview-insp-value"
              onClick={(e) => {
                if (def) return editRow(def, e.currentTarget)
                triggerRef.current = e.currentTarget
                setEditing({ id, mode: 'picker' })
              }}
            >
              {editing?.id === id && editing.mode === 'editor' && def ? (
                <PropertyEditor
                  initial={(() => {
                    const v = resolveFieldValue(row, id, schema)
                    return v.kind === 'number' || v.kind === 'url' ? String(v.value) : ''
                  })()}
                  numeric={def.type === 'number'}
                  validate={def.type === 'url' ? isValidLink : undefined}
                  onCommit={(raw) => {
                    const t = raw.trim()
                    commitValue(
                      id,
                      t === ''
                        ? null
                        : def.type === 'number'
                          ? { kind: 'number', value: Number(t) }
                          : { kind: 'url', value: t },
                    )
                    setEditing(null)
                  }}
                  onCancel={() => setEditing(null)}
                />
              ) : (
                (Cell({
                  row,
                  column: col,
                  ctx,
                  hideIcon: false,
                  style: { look: 'pill' },
                }) ?? <span className="pgpreview-insp-empty">Empty</span>)
              )}
            </span>
              </div>
            )
            })}
          </div>
        ))}
        {schema.some((d) => !isAssigned(d.id)) && (
          <button
            type="button"
            ref={addRef}
            className={cx('pgpreview-insp-add', text.footnote.standard)}
            onClick={() => setAddOpen(true)}
          >
            <Icon name="plus" size={11} />
            <span>Add Property</span>
          </button>
        )}
      </div>
      {rowMenu && (
        <>
          <span
            ref={rowMenuRef}
            aria-hidden
            style={{ position: 'fixed', left: rowMenu.x, top: rowMenu.y, width: 0, height: 0 }}
          />
          <PickerMenu solid open onDismiss={() => setRowMenu(null)} triggerRef={rowMenuRef} center>
            <div className="nav-row-menu">
              <MenuItem
                leading={<Icon name="x" size={13} />}
                onClick={() => {
                  commitValue(rowMenu.id, null)
                  setRevealed((prev) => new Set([...prev].filter((r) => r !== rowMenu.id)))
                  setRowMenu(null)
                }}
              >
                Remove Property
              </MenuItem>
            </div>
          </PickerMenu>
        </>
      )}
      {addOpen && (
        <PickerMenu solid open onDismiss={() => setAddOpen(false)} triggerRef={addRef}>
          {/* The Group/Sort property menu, borrowed whole — tight MenuItem rows. */}
          <div className="nav-row-menu">
            {schema
              .filter((d) => !isAssigned(d.id))
              .map((d) => (
                <MenuItem
                  key={d.id}
                  leading={
                    <Icon
                      name={asRenderableIcon(d.icon) ?? propertyTypeIconName(d.type) ?? 'tag'}
                      size={13}
                    />
                  }
                  onClick={() => {
                    setAddOpen(false)
                    setRevealed((prev) => new Set([...prev, d.id]))
                    if (d.type === 'checkbox') {
                      commitValue(d.id, { kind: 'checkbox', value: true })
                      return
                    }
                    // The editor anchors to the revealed row's VALUE field on the right — the row
                    // mounts next frame.
                    requestAnimationFrame(() => {
                      triggerRef.current =
                        document.querySelector<HTMLElement>(
                          `[data-insp-id="${d.id}"] .pgpreview-insp-value`,
                        ) ?? addRef.current
                      if (d.type === 'datetime') setEditing({ id: d.id, mode: 'date' })
                      else if (d.type === 'number' || d.type === 'url')
                        setEditing({ id: d.id, mode: 'editor' })
                      else if (d.type !== 'file' && d.type !== 'last_edited_time')
                        setEditing({ id: d.id, mode: 'picker' })
                    })
                  }}
                >
                  {d.name}
                </MenuItem>
              ))}
          </div>
        </PickerMenu>
      )}
      <div className="pgpreview-insp-subfield">
        <NavCrumbs path={location} className="pgpreview-insp-loc" iconSize={11} />
      </div>
      {editingDef && editing?.mode === 'picker' && (
        <PropertyPicker
          def={editingDef}
          current={resolveFieldValue(row, editing.id, schema)}
          open
          triggerRef={triggerRef}
          {...(editingDef.type === 'context' && tree
            ? {
                contextOptions: contextOptionsFor(
                  TIER_LEVEL_BY_ID[editing.id] ??
                    schema.find((d) => d.id === editing.id)?.context_target?.tier,
                  tree,
                ),
              }
            : {})}
          onCommit={(v) => {
            if (TIER_LEVEL_BY_ID[editing.id])
              commitTier(editing.id, v?.kind === 'context' ? v.value : [])
            else commitValue(editing.id, v)
          }}
          onDismiss={closeEditing}
        />
      )}
      {editing?.mode === 'date' && (
        <PickerMenu solid open onDismiss={closeEditing} triggerRef={triggerRef}>
          <CalendarPicker
            range={false}
            value={(() => {
              const v = resolveFieldValue(row, editing.id, schema)
              return v.kind === 'datetime' ? v.value : null
            })()}
            timeFormat={tree?.timeFormat}
            formatDateValue={(k) => formatDate(k, 'full', 'none')}
            onChange={(iso) => {
              commitValue(editing.id, iso ? { kind: 'datetime', value: iso } : null)
            }}
          />
        </PickerMenu>
      )}
    </div>
  )
}
