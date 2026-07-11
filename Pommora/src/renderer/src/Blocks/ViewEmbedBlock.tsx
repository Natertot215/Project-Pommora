import { useEffect, useRef, useState } from 'react'
import type { ViewBlockEntry } from '@shared/blocks'
import type { CollectionNode, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { DEFAULT_VIEW_ID, mintDefaultView, mintNewView, type SavedView } from '@shared/views'
import { Icon, iconNameOr } from '@renderer/design-system/symbols'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu'
import { AccessoryButton, Menu, MenuBottomRow, MenuItem, MenuScrollFrame } from '@renderer/design-system/components/menu'
import { titleInput as rowInput } from '@renderer/design-system/components/menu/menu.css'
import { activeRow } from '@renderer/Toolbar/viewDropdown.css'
import { EditableInput } from '@renderer/Components/EditableInput'
import { IconPicker } from '@renderer/Components/IconPicker'
import { findCollection, findCollectionForSet, findSet } from '@renderer/Detail/Scope'
import { TableView } from '@renderer/Detail/Views/Table/TableView'
import { SettingsPane } from '@renderer/Components/Detail/SettingsPane'
import { ViewEmbedScopeProvider } from '@renderer/Embeds/ViewEmbedScope'
import { useSession } from '@renderer/store'
import { PICKER_MAX_H } from './handleMenu.css'
import * as s from './viewEmbed.css'

/** The copied config is ours by construction; a foreign or malformed one degrades to the
 *  blank default (repair-not-reject). Every degrade path re-stamps `fallbackId` — a repaired
 *  config must never carry the DEFAULT_VIEW_ID sentinel (it keys viewOrders per-machine and
 *  would persist on the next config edit), and never a random id (coerce runs per render). */
function coerceConfig(raw: unknown, schema: PropertyDefinition[], fallbackId: string): SavedView {
  const v = raw as SavedView | null
  const shapeOk =
    typeof v === 'object' &&
    v !== null &&
    typeof v.id === 'string' &&
    typeof v.name === 'string' &&
    typeof v.type === 'string' &&
    (['property_order', 'hidden_properties', 'sort'] as const).every((k) => v[k] === undefined || Array.isArray(v[k]))
  if (!shapeOk) return { ...mintDefaultView(schema), id: fallbackId }
  return v.id === DEFAULT_VIEW_ID ? { ...v, id: fallbackId } : v
}

/** The ####-scale display title — click flips it to an in-place rename field (a doc title,
 *  no menu needed); Enter/blur commit, Escape reverts. Empty commits clear back to the source. */
function EmbedTitle({ title, onCommit }: { title: string; onCommit: (next: string) => void }): React.JSX.Element {
  const [editing, setEditing] = useState(false)
  const [value, setValue] = useState(title)
  const reverting = useRef(false) // Escape sets this so the blur it triggers doesn't commit
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => setValue(title), [title])
  useEffect(() => {
    if (editing) {
      inputRef.current?.focus()
      inputRef.current?.select()
    }
  }, [editing])

  const commit = (): void => {
    setEditing(false)
    if (value.trim() !== title) onCommit(value)
  }

  if (!editing)
    return (
      // biome-ignore lint/a11y/noStaticElementInteractions: click-to-rename text, the doc-title idiom.
      <span className={s.titleText} onClick={() => setEditing(true)}>
        {title}
      </span>
    )
  return (
    <input
      ref={inputRef}
      className={s.titleInput}
      value={value}
      spellCheck={false}
      onChange={(e) => setValue(e.target.value)}
      onKeyDown={(e) => {
        if (e.key === 'Enter') {
          e.preventDefault()
          commit()
        } else if (e.key === 'Escape') {
          reverting.current = true
          setValue(title)
          setEditing(false)
        }
      }}
      onBlur={() => {
        if (reverting.current) {
          reverting.current = false
          return
        }
        commit()
      }}
    />
  )
}

// The view-embed tile (H-4/H-5): the title row (editable ####, right-click chrome menu) over the
// view switcher (pills or a dropdown, right-click presentation menu) over the REAL TableView at
// the fixed embed zoom, all inside the ViewEmbedScope — resolution reads the payload config,
// config writes land on it, data writes flow through to the source (D-12).
export function ViewEmbedBlock({
  entry,
  mutateEntry
}: {
  entry: ViewBlockEntry
  mutateEntry: (entryId: string, fn: (raw: Record<string, unknown>) => Record<string, unknown>) => void
}): React.JSX.Element {
  const tree = useSession((st) => st.tree)
  const [cfgOpen, setCfgOpen] = useState(false)
  const [listOpen, setListOpen] = useState(false)
  const [renaming, setRenaming] = useState<number | null>(null)
  const [iconFor, setIconFor] = useState<number | null>(null)
  const btnRef = useRef<HTMLButtonElement>(null)
  const dropRef = useRef<HTMLButtonElement>(null)

  const index = Math.min(entry.active ?? 0, entry.views.length - 1)
  const embedded = entry.views[index]
  const source: CollectionNode | SetNode | undefined =
    embedded && tree ? (findCollection(tree, embedded.source_id) ?? findSet(tree, embedded.source_id)) : undefined
  if (!embedded || !source || !tree) return <div className="blk-inert" /> // dead source — inert, space holds (E-2)

  const schemaCollection = source.kind === 'collection' ? source : findCollectionForSet(tree, source.id)
  const schema = schemaCollection?.properties ?? []
  const views = entry.views.map((v, i) => coerceConfig(v.config, schema, `embed:${entry.id}:${i}`))
  const view = views[index]

  const titleShown = entry.title !== false
  const iconShown = entry.icon !== false
  const labeled = (entry.view_button ?? 'labeled') === 'labeled'
  const dropdown = entry.view_style === 'dropdown'

  // Every write transforms the RAW entry (raw spreads — foreign keys survive, E-1); chrome
  // defaults are stored as ABSENT keys, so clearing a toggle deletes it rather than pinning it.
  const patchEntry = (patch: Record<string, unknown>): void =>
    mutateEntry(entry.id, (raw) => {
      const next = { ...raw }
      for (const [k, v] of Object.entries(patch)) {
        if (v === undefined) delete next[k]
        else next[k] = v
      }
      return next
    })
  const persistConfig = (i: number, config: SavedView): void =>
    mutateEntry(entry.id, (raw) => {
      const arr = Array.isArray(raw.views) ? [...(raw.views as unknown[])] : []
      const el = arr[i]
      if (typeof el !== 'object' || el === null) return raw
      arr[i] = { ...(el as Record<string, unknown>), config }
      return { ...raw, views: arr }
    })
  // A new view mints blank on the ACTIVE view's source and becomes active. Its payload-local id
  // takes the first free slot in the coerce family — deletes shift indexes, so the next slot
  // number can already be taken by a survivor and a plain length-stamp would collide (viewOrders
  // keys on config id; two views must never share one).
  const addView = (): void =>
    mutateEntry(entry.id, (raw) => {
      const arr = Array.isArray(raw.views) ? [...(raw.views as unknown[])] : []
      const used = new Set(arr.map((el) => ((el as { config?: { id?: unknown } })?.config?.id as string) ?? ''))
      let slot = arr.length
      while (used.has(`embed:${entry.id}:${slot}`)) slot++
      arr.push({ source_id: source.id, config: { ...mintNewView('Untitled', schema), id: `embed:${entry.id}:${slot}` } })
      return { ...raw, views: arr, active: arr.length - 1 }
    })
  const deleteView = (i: number): void =>
    mutateEntry(entry.id, (raw) => {
      const arr = Array.isArray(raw.views) ? [...(raw.views as unknown[])] : []
      if (arr.length <= 1) return raw // the switcher never empties (views min(1))
      arr.splice(i, 1)
      const cur = typeof raw.active === 'number' ? raw.active : 0
      return { ...raw, views: arr, active: Math.min(cur > i ? cur - 1 : cur, arr.length - 1) }
    })
  const commitTitle = (next: string): void => {
    const t = next.trim()
    patchEntry({ display_title: !t || t === source.title ? undefined : t })
  }

  const titleMenu = async (e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    const action = await window.nexus.viewEmbedTitleMenu(iconShown)
    if (action === 'toggle-icon') patchEntry({ icon: iconShown ? false : undefined })
    else if (action === 'hide-title') patchEntry({ title: false })
  }
  const areaMenu = async (e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    const action = await window.nexus.viewEmbedAreaMenu({
      viewButton: labeled ? 'labeled' : 'icon',
      viewStyle: dropdown ? 'dropdown' : 'toolbar',
      titleShown
    })
    if (action === 'toggle-pill-titles') patchEntry({ view_button: labeled ? 'icon' : undefined })
    else if (action === 'show-title') patchEntry({ title: undefined })
    else if (action === 'new-view') addView()
    else if (action === 'style-dropdown') patchEntry({ view_style: 'dropdown' })
    else if (action === 'style-toolbar') patchEntry({ view_style: undefined })
  }
  // A pill/list row's own menu — the ViewPane row family (Rename / Edit Icon / Delete).
  const rowMenu = async (i: number, e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    e.stopPropagation() // the switcher row underneath owns the area menu
    const action = await window.nexus.viewRowMenu(entry.views.length > 1)
    if (action === 'view:rename') setRenaming(i)
    else if (action === 'view:edit-icon') setIconFor(i)
    else if (action === 'view:delete') deleteView(i)
  }

  const renameField = (i: number): React.JSX.Element => (
    <EditableInput
      value={views[i].name}
      className={rowInput}
      caretAtEnd
      onCommit={(next) => {
        setRenaming(null)
        if (next && next !== views[i].name) persistConfig(i, { ...views[i], name: next })
      }}
      onCancel={() => setRenaming(null)}
    />
  )

  const configButton = (
    <button ref={btnRef} type="button" className={s.configBtn} aria-label="View settings" onClick={() => setCfgOpen(true)}>
      <Icon name="sliders-horizontal" size={14} />
    </button>
  )

  const switcher = dropdown ? (
    <button ref={dropRef} type="button" className={s.pill} onClick={() => setListOpen(true)}>
      <Icon name={iconNameOr(view.icon, 'table')} size={12} />
      {labeled && <span>{view.name}</span>}
      <Icon name="chevron-down" size={10} />
    </button>
  ) : (
    <>
      {views.map((v, i) => (
        <button
          key={`${i}:${v.id}`}
          type="button"
          className={i === index ? `${s.pill} ${s.pillActive}` : s.pill}
          onClick={renaming === i ? undefined : () => patchEntry({ active: i })}
          onContextMenu={(e) => void rowMenu(i, e)}
        >
          <Icon name={iconNameOr(v.icon, 'table')} size={12} />
          {renaming === i ? renameField(i) : labeled && <span>{v.name}</span>}
        </button>
      ))}
      <AccessoryButton icon="plus" size={12} box={20} ariaLabel="New View" onClick={addView} />
    </>
  )

  return (
    <ViewEmbedScopeProvider value={{ source, view, persistConfig: (next) => persistConfig(index, next) }}>
      <div className={s.tile}>
        {titleShown && (
          // biome-ignore lint/a11y/noStaticElementInteractions: right-click chrome menu on the title row.
          <div className={s.titleRow} onContextMenu={(e) => void titleMenu(e)}>
            {iconShown && <Icon name={iconNameOr(view.icon, 'table')} size={15} />}
            <EmbedTitle title={entry.display_title ?? source.title} onCommit={commitTitle} />
            {configButton}
          </div>
        )}
        {/* biome-ignore lint/a11y/noStaticElementInteractions: right-click presentation menu on the switcher area. */}
        <div className={s.switcherRow} onContextMenu={(e) => void areaMenu(e)}>
          {switcher}
          {!titleShown && (
            <>
              <span className={s.spacer} />
              {configButton}
            </>
          )}
        </div>
        <div className={s.body}>
          <TableView key={source.id} source={source} />
        </div>
        {/* PickerMenu owns the anchoring — body portal (H-11), scroll/resize re-measure,
            collision flip; a hand-rolled fixed portal detaches when the surface scrolls. */}
        <PickerMenu open={cfgOpen} onDismiss={() => setCfgOpen(false)} triggerRef={btnRef}>
          <SettingsPane />
        </PickerMenu>
        {/* Dropdown mode's view list — the ViewPane's rows without the edit chevrons (H-5:
            per-view editing lives behind the Settings affordance, not in the switcher). */}
        <PickerMenu open={listOpen} onDismiss={() => setListOpen(false)} triggerRef={dropRef}>
          <div className={s.listPane}>
            <MenuScrollFrame
              maxHeight={PICKER_MAX_H}
              footer={
                <MenuBottomRow
                  leading={<AccessoryButton icon="plus" size={12} box={20} ariaLabel="New View" onClick={addView} />}
                />
              }
            >
              <Menu>
                {views.map((v, i) => (
                  <MenuItem
                    key={`${i}:${v.id}`}
                    className={i === index ? activeRow : undefined}
                    leading={<Icon name={iconNameOr(v.icon, 'table')} size={16} />}
                    onClick={renaming === i ? undefined : () => patchEntry({ active: i })}
                    onContextMenu={(e) => void rowMenu(i, e)}
                  >
                    {renaming === i ? renameField(i) : v.name}
                  </MenuItem>
                ))}
              </Menu>
            </MenuScrollFrame>
          </div>
        </PickerMenu>
        <IconPicker
          open={iconFor !== null}
          onClose={() => setIconFor(null)}
          value={iconFor !== null ? views[iconFor]?.icon : undefined}
          onSelect={(icon) => {
            if (iconFor !== null) persistConfig(iconFor, { ...views[iconFor], icon })
          }}
        />
      </div>
    </ViewEmbedScopeProvider>
  )
}
