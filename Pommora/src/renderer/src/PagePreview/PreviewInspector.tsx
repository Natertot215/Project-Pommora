import { useEffect, useMemo, useRef, useState } from 'react'
import type { PropertyDefinition } from '@shared/properties'
import type { PropertyValue } from '@shared/propertyValue'
import { applyPropertyValue } from '@shared/propertyValue'
import type { PageFrontmatter } from '@shared/schemas'
import type { NexusTree, ResolvedColumn, ViewRow } from '@shared/types'
import { cx } from '@renderer/design-system/cx'
import { Icon } from '@renderer/design-system/symbols'
import { text } from '@renderer/design-system/tokens'
import { CalendarPicker } from '@renderer/design-system/components/CalendarPicker/CalendarPicker'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu/PickerMenu'
import { Cell } from '../Detail/Views/Table/Cell'
import { buildContextsById, type ResolveContext } from '../Detail/Views/Table/resolveContext'
import { contextOptionsFor } from '../Detail/Views/pipeline/contextOptions'
import { TIER_LEVEL_BY_ID } from '../Detail/Views/Table/columnLabel'
import { PropertyEditor } from '../Detail/Views/PropertyEditing/PropertyEditor'
import { PropertyPicker } from '../Detail/Views/PropertyEditing/PropertyPicker'
import { formatDate } from '../Detail/Views/PropertyEditing/formatValue'
import { resolveFieldValue } from '../Detail/Views/pipeline/value'
import { isValidLink } from '@shared/links'
import { RESERVED_PROPERTY_ID } from '@shared/properties'
import { flushPreviewPage } from '../Detail/pageFlush'
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
  const [editingTitle, setEditingTitle] = useState(false)
  const [editing, setEditing] = useState<Editing>(null)
  const triggerRef = useRef<HTMLElement | null>(null)

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
  const ctx = useMemo<ResolveContext | null>(
    () => (tree ? { schema, contextsById: buildContextsById(tree), labels: tree.labels } : null),
    [tree, schema],
  )
  const row = useMemo<ViewRow | null>(
    () => (fm ? { id: target.id, title, icon: fm.icon, path: target.path, frontmatter: fm } : null),
    [fm, title, target],
  )

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
  // I-13: the rename must not race the editor's pending body — flush it to the OLD path first
  // (a self-rename would otherwise refuse at the dead path and drop the edit).
  const commitTitle = async (raw: string): Promise<void> => {
    const next = raw.trim()
    if (next === '' || next === title) return
    setTitle(next)
    await flushPreviewPage()
    void mutate({ op: 'rename', path: target.path, kind: 'page', newName: next })
  }
  // I-14: the PageHeader banner mechanism, preview-scoped (cover = the banner field).
  const setBanner = async (dataUrl: string | null): Promise<void> => {
    if (await mutate({ op: 'setBanner', path: target.path, kind: 'page', dataUrl }))
      setFm((prev) => (prev ? { ...prev, cover: dataUrl ?? undefined } : prev))
  }
  const changeBanner = async (): Promise<void> => {
    const dataUrl = await window.nexus.pickImage()
    if (dataUrl) await setBanner(dataUrl)
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
  const tierRows: Array<{ id: string; label: string }> = [
    { id: RESERVED_PROPERTY_ID.tier1, label: ctx.labels.area.plural },
    { id: RESERVED_PROPERTY_ID.tier2, label: ctx.labels.topic.plural },
    { id: RESERVED_PROPERTY_ID.tier3, label: ctx.labels.project.plural },
  ]

  return (
    <div className="pgpreview-insp edge-fade">
      {editingTitle ? (
        <PropertyEditor
          initial={title}
          onCommit={(raw) => {
            setEditingTitle(false)
            void commitTitle(raw)
          }}
          onCancel={() => setEditingTitle(false)}
        />
      ) : (
        // biome-ignore lint/a11y/useKeyWithClickEvents: pointer-first edit entry, like cells
        <span
          className={cx('pgpreview-insp-title', text.control.emphasized)}
          onClick={() => setEditingTitle(true)}
        >
          {title}
        </span>
      )}
      <div className={cx('pgpreview-insp-banner', text.caption.standard)}>
        <button type="button" onClick={() => void changeBanner()}>
          {fm.cover ? 'Change Banner' : 'Add Banner'}
        </button>
        {fm.cover && (
          <button type="button" onClick={() => void setBanner(null)}>
            Remove
          </button>
        )}
      </div>
      {[
        ...tierRows.map((t) => ({ def: null, ...t })),
        ...schema.map((d) => ({ def: d, id: d.id, label: d.name })),
      ].map(({ def, id, label }) => {
        const col: ResolvedColumn = { id, kind: def ? 'property' : 'tier' }
        return (
          <div key={id} className="pgpreview-insp-row">
            <span className={cx('pgpreview-insp-label', text.caption.standard)}>
              {def?.icon ? <Icon name={def.icon as never} size={12} /> : null}
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
          onDismiss={() => setEditing(null)}
        />
      )}
      {editing?.mode === 'date' && (
        <PickerMenu solid open onDismiss={() => setEditing(null)} triggerRef={triggerRef}>
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
