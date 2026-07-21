import { useEffect, useRef, useState } from 'react'
import type { ViewBlockEntry } from '@shared/blocks'
import type { CollectionNode, SetNode } from '@shared/types'
import type { PropertyDefinition } from '@shared/properties'
import { DEFAULT_VIEW_ID, mintDefaultView, mintNewView, type SavedView } from '@shared/views'
import { Icon, iconNameOr } from '@renderer/design-system/symbols'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu'
import {
  AccessoryButton,
  Menu,
  MenuBottomRow,
  MenuItem,
  MenuScrollFrame,
} from '@renderer/design-system/components/menu'
import { titleInput as rowInput } from '@renderer/design-system/components/menu/menu.css'
import { reorder, SortableZone, useDragItem } from '@renderer/design-system/interactions/drag'
import { activeRow } from '@renderer/Toolbar/viewDropdown.css'
import { EditableInput } from '@renderer/Components/EditableInput'
import { IconPicker } from '@renderer/Components/IconPicker'
import { findCollection, findCollectionForSet, findSet } from '@renderer/Detail/Scope'
import { ViewRenderer } from '@renderer/Detail/Views/ViewRenderer'
import { SettingsPane } from '@renderer/Components/Detail/SettingsPane'
import { ViewEmbedScopeProvider } from '@renderer/Embeds/ViewEmbedScope'
import { useSession } from '@renderer/store'
import { PICKER_MAX_H } from './handleMenu.css'
import { PILL_ICON } from './viewEmbed.css'
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
    (['property_order', 'hidden_properties', 'sort'] as const).every(
      (k) => v[k] === undefined || Array.isArray(v[k]),
    )
  if (!shapeOk) return { ...mintDefaultView(schema), id: fallbackId }
  return v.id === DEFAULT_VIEW_ID ? { ...v, id: fallbackId } : v
}

/** A fresh shallow copy of the entry's raw `views` array — a caller can mutate then return it
 *  without touching the input (elements stay the untouched `{ source_id, config }` records). */
const rawViews = (raw: Record<string, unknown>): unknown[] =>
  Array.isArray(raw.views) ? [...(raw.views as unknown[])] : []

/** A view's leading glyph, falling back to the table icon when unset (legacy `'tablecells'` too). */
const viewIcon = (v: SavedView): string => iconNameOr(v.icon, 'table')

/** The display title — sized by markdownPM's own `.md-h{level}` heading class (they're the same code,
 *  so a title reads uniform with any rendered heading). Editing happens in place on the SAME element via
 *  contentEditable — no input swap, so the field is the text itself: the caret drops in and it reads
 *  smooth. Enter/blur commit, Escape reverts; an empty commit clears back to the source. */
function EmbedTitle({
  title,
  level,
  onCommit,
}: {
  title: string
  level: number
  onCommit: (next: string) => void
}): React.JSX.Element {
  const [editing, setEditing] = useState(false)
  const ref = useRef<HTMLSpanElement>(null)
  const reverting = useRef(false) // Escape sets this so the blur it triggers doesn't commit

  // On entering edit, focus and select the whole title so a first keystroke replaces it.
  useEffect(() => {
    const el = ref.current
    if (!editing || !el) return
    el.focus()
    const range = document.createRange()
    range.selectNodeContents(el)
    const sel = window.getSelection()
    sel?.removeAllRanges()
    sel?.addRange(range)
  }, [editing])

  const commit = (): void => {
    setEditing(false)
    const next = (ref.current?.textContent ?? '').trim()
    if (next !== title) onCommit(next)
  }

  return (
    <span
      ref={ref}
      className={`${s.titleText} md-h${level}`}
      contentEditable={editing}
      suppressContentEditableWarning
      spellCheck={false}
      role="textbox"
      tabIndex={editing ? 0 : undefined}
      onClick={editing ? undefined : () => setEditing(true)}
      onKeyDown={
        editing
          ? (e) => {
              if (e.key === 'Enter') {
                e.preventDefault()
                commit()
              } else if (e.key === 'Escape') {
                reverting.current = true
                if (ref.current) ref.current.textContent = title
                setEditing(false)
              }
            }
          : undefined
      }
      onBlur={
        editing
          ? () => {
              if (reverting.current) {
                reverting.current = false
                return
              }
              commit()
            }
          : undefined
      }
    >
      {title}
    </span>
  )
}

/** One draggable view pill (toolbar mode). Reorder rides the shared drag engine (`useDragItem`),
 *  the same mechanism the sidebar ribbon uses; enter/exit slides run off the css presence classes. */
function ViewPill({
  id,
  view,
  active,
  entering,
  exiting,
  labeled,
  renameNode,
  onSwitch,
  onMenu,
  onAnimEnd,
}: {
  id: string
  view: SavedView
  active: boolean
  entering: boolean
  exiting: boolean
  labeled: boolean
  renameNode: React.ReactNode | null
  onSwitch: () => void
  onMenu: (e: React.MouseEvent) => void
  onAnimEnd: () => void
}): React.JSX.Element {
  const { setNodeRef, style, handle } = useDragItem(id)
  const cls = [s.pill, active && s.pillActive, entering && s.pillEntering, exiting && s.pillExiting]
    .filter(Boolean)
    .join(' ')
  return (
    <button
      ref={setNodeRef}
      style={style}
      {...handle}
      type="button"
      className={cls}
      onClick={renameNode ? undefined : onSwitch}
      onContextMenu={onMenu}
      onAnimationEnd={onAnimEnd}
    >
      <Icon name={viewIcon(view)} size={PILL_ICON} />
      {renameNode ?? (labeled && <span>{view.name}</span>)}
    </button>
  )
}

// The view-embed tile (H-4/H-5): the title row (editable ####, right-click chrome menu) over the
// view switcher (pills or a dropdown, right-click presentation menu) over the REAL TableView at
// the fixed embed zoom, all inside the ViewEmbedScope — resolution reads the payload config,
// config writes land on it, data writes flow through to the source (D-12).
export function ViewEmbedBlock({
  entry,
  mutateEntry,
  onActivate,
}: {
  entry: ViewBlockEntry
  mutateEntry: (
    entryId: string,
    fn: (raw: Record<string, unknown>) => Record<string, unknown>,
  ) => void
  /** Mark this tile the surface's active one — a view has no text-edit mode, so interacting with it
   *  (any pointerdown inside) is its "busy" signal, which corner-scopes its drag handle like an editor. */
  onActivate?: () => void
}): React.JSX.Element {
  const tree = useSession((st) => st.tree)
  const [cfgOpen, setCfgOpen] = useState(false)
  const [listOpen, setListOpen] = useState(false)
  const [renaming, setRenaming] = useState<number | null>(null)
  const [iconFor, setIconFor] = useState<number | null>(null)
  const [exitingId, setExitingId] = useState<string | null>(null)
  const [enteringIds, setEnteringIds] = useState<Set<string>>(() => new Set())
  const prevIdsRef = useRef<Set<string> | null>(null)
  const viewsRef = useRef<SavedView[]>([])
  const btnRef = useRef<HTMLButtonElement>(null)
  const dropRef = useRef<HTMLButtonElement>(null)

  const index = Math.min(entry.active ?? 0, entry.views.length - 1)
  // View-switch slide direction: a higher index (a pill to the right) enters from the right (+), a lower
  // one from the left (−). prevIndexRef holds the last-committed index so the offset reads at switch time.
  const prevIndexRef = useRef(index)
  const slideFrom =
    index > prevIndexRef.current ? '24px' : index < prevIndexRef.current ? '-24px' : '0px'
  useEffect(() => {
    prevIndexRef.current = index
  }, [index])
  const embedded = entry.views[index]
  const source: CollectionNode | SetNode | undefined =
    embedded && tree
      ? (findCollection(tree, embedded.source_id) ?? findSet(tree, embedded.source_id))
      : undefined

  const schemaCollection =
    source && source.kind !== 'collection' ? findCollectionForSet(tree, source.id) : source
  const schema = (schemaCollection as CollectionNode | undefined)?.properties ?? []
  const views = source
    ? entry.views.map((v, i) => coerceConfig(v.config, schema, `embed:${entry.id}:${i}`))
    : []
  viewsRef.current = views
  const idKey = views.map((v) => v.id).join(',')

  // A view added since the last render slides in (a fresh DOM node whose entering class survives
  // re-renders because it's state, not derived — a derived flag would clear mid-animation).
  useEffect(() => {
    const prev = prevIdsRef.current
    const cur = new Set(viewsRef.current.map((v) => v.id))
    if (prev) {
      const added = [...cur].filter((id) => !prev.has(id))
      if (added.length) setEnteringIds((s0) => new Set([...s0, ...added]))
    }
    prevIdsRef.current = cur
  }, [idKey])

  if (!embedded || !source || !tree) return <div className="blk-inert" /> // dead source — inert, space holds (E-2)

  const view = views[index]
  const titleShown = entry.title !== false
  const iconShown = entry.icon !== false
  const titleLevel = entry.title_level ?? 4 // #### default
  const labeled = (entry.view_button ?? 'labeled') === 'labeled'
  const dropdown = entry.view_style === 'dropdown'

  const locked = entry.locked ?? false
  // Every write transforms the RAW entry (raw spreads — foreign keys survive, E-1); chrome
  // defaults are stored as ABSENT keys, so clearing a toggle deletes it rather than pinning it.
  // While locked (B-5) this is the freeze for all chrome (title rename, hide title/icon, heading size,
  // pill/switcher style): only the lock toggle itself and the active-view SWITCH (viewing, not editing)
  // still write — so a locked tile's title + presentation are frozen to match the handle menu's promise.
  const patchEntry = (patch: Record<string, unknown>): void => {
    if (locked && !('locked' in patch) && !('active' in patch)) return
    mutateEntry(entry.id, (raw) => {
      const next = { ...raw }
      for (const [k, v] of Object.entries(patch)) {
        if (v === undefined) delete next[k]
        else next[k] = v
      }
      return next
    })
  }
  // The lock toggle rides patchEntry's `locked` exemption above, so you can always unlock.
  const setLocked = (v: boolean): void => patchEntry({ locked: v ? true : undefined })
  const persistConfig = (i: number, config: SavedView): void => {
    if (locked) return // B-5: every config surface routes through here, so this one gate freezes them all
    mutateEntry(entry.id, (raw) => {
      const arr = rawViews(raw)
      const el = arr[i]
      if (typeof el !== 'object' || el === null) return raw
      arr[i] = { ...(el as Record<string, unknown>), config }
      return { ...raw, views: arr }
    })
  }
  // A new view mints blank on the ACTIVE view's source and becomes active. Its payload-local id
  // takes the first free slot in the coerce family — deletes shift indexes, so the next slot
  // number can already be taken by a survivor and a plain length-stamp would collide (viewOrders
  // keys on config id; two views must never share one).
  const addView = (): void => {
    if (locked) return
    mutateEntry(entry.id, (raw) => {
      const arr = rawViews(raw)
      const used = new Set(
        arr.map((el) => ((el as { config?: { id?: unknown } })?.config?.id as string) ?? ''),
      )
      let slot = arr.length
      while (used.has(`embed:${entry.id}:${slot}`)) slot++
      arr.push({
        source_id: source.id,
        config: { ...mintNewView('Untitled', schema), id: `embed:${entry.id}:${slot}` },
      })
      return { ...raw, views: arr, active: arr.length - 1 }
    })
  }
  const deleteViewAt = (i: number): void => {
    if (locked) return // the sink for BOTH paths (dropdown row menu = un-animated; pill = via finishExit)
    mutateEntry(entry.id, (raw) => {
      const arr = rawViews(raw)
      if (arr.length <= 1) return raw // the switcher never empties (views min(1))
      arr.splice(i, 1)
      const cur = typeof raw.active === 'number' ? raw.active : 0
      return { ...raw, views: arr, active: Math.min(cur > i ? cur - 1 : cur, arr.length - 1) }
    })
  }
  // Toolbar delete slides out first: mark the pill exiting; its animationend commits the removal.
  const beginDeleteView = (i: number): void => {
    if (locked || entry.views.length <= 1) return
    setExitingId(views[i].id)
  }
  const finishExit = (id: string): void => {
    const i = viewsRef.current.findIndex((v) => v.id === id)
    if (i >= 0) deleteViewAt(i)
    setExitingId(null)
  }
  const reorderViews = (activeId: string, overId: string): void => {
    if (locked) return
    mutateEntry(entry.id, (raw) => {
      const arr = rawViews(raw)
      const seq = reorder(
        viewsRef.current.map((v, i) => ({ id: v.id, i })),
        activeId,
        overId,
      )
      const next = seq.map((x) => arr[x.i]).filter((x) => x != null)
      const newActive = seq.findIndex((x) => x.i === index)
      return { ...raw, views: next, active: newActive >= 0 ? newActive : 0 }
    })
  }
  const commitTitle = (next: string): void => {
    const t = next.trim()
    patchEntry({ display_title: !t || t === source.title ? undefined : t })
  }

  const titleMenu = async (e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    const action = await window.nexus.viewEmbedTitleMenu({ iconShown, level: titleLevel })
    if (action === 'toggle-icon') patchEntry({ icon: iconShown ? false : undefined })
    else if (action === 'hide-title') patchEntry({ title: false })
    else if (action?.startsWith('size-')) {
      const n = Number(action.slice(5))
      patchEntry({ title_level: n === 4 ? undefined : n }) // default level stores absent
    }
  }
  const areaMenu = async (e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    const action = await window.nexus.viewEmbedAreaMenu({
      viewButton: labeled ? 'labeled' : 'icon',
      viewStyle: dropdown ? 'dropdown' : 'toolbar',
      titleShown,
    })
    if (action === 'toggle-pill-titles') patchEntry({ view_button: labeled ? 'icon' : undefined })
    else if (action === 'show-title') patchEntry({ title: undefined })
    else if (action === 'new-view') addView()
    else if (action === 'style-dropdown') patchEntry({ view_style: 'dropdown' })
    else if (action === 'style-toolbar') patchEntry({ view_style: undefined })
  }
  // A pill/list row's own menu — the ViewPane row family (Rename / Edit Icon / Delete). `animate`
  // routes the pill's delete through the slide-out; the dropdown list removes in place.
  const rowMenu = async (i: number, e: React.MouseEvent, animate: boolean): Promise<void> => {
    e.preventDefault()
    e.stopPropagation() // the switcher row underneath owns the area menu
    const action = await window.nexus.viewRowMenu(entry.views.length > 1)
    if (action === 'view:rename') setRenaming(i)
    else if (action === 'view:edit-icon') setIconFor(i)
    else if (action === 'view:delete') (animate ? beginDeleteView : deleteViewAt)(i)
  }
  const pillAnimEnd = (id: string): void => {
    if (exitingId === id) finishExit(id)
    else if (enteringIds.has(id))
      setEnteringIds((s0) => (s0.has(id) ? new Set([...s0].filter((x) => x !== id)) : s0))
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
    <button
      ref={btnRef}
      type="button"
      className={cfgOpen ? `${s.configBtn} ${s.configBtnActive}` : s.configBtn}
      aria-label="View settings"
      onClick={() => setCfgOpen(true)}
    >
      <Icon name="sliders-horizontal" size={14} />
    </button>
  )

  const newViewButton = (
    <AccessoryButton icon="plus" size={12} box={20} ariaLabel="New View" onClick={addView} />
  )

  const switcher = dropdown ? (
    <button ref={dropRef} type="button" className={s.pill} onClick={() => setListOpen(true)}>
      <Icon name={viewIcon(view)} size={PILL_ICON} />
      {labeled && <span>{view.name}</span>}
      <Icon name="chevron-down" size={10} />
    </button>
  ) : (
    <>
      <SortableZone items={views.map((v) => v.id)} layout="list" axis="x" onReorder={reorderViews}>
        {views.map((v, i) => (
          <ViewPill
            key={v.id}
            id={v.id}
            view={v}
            active={i === index}
            entering={enteringIds.has(v.id)}
            exiting={exitingId === v.id}
            labeled={labeled}
            renameNode={renaming === i ? renameField(i) : null}
            onSwitch={() => patchEntry({ active: i })}
            onMenu={(e) => void rowMenu(i, e, true)}
            onAnimEnd={() => pillAnimEnd(v.id)}
          />
        ))}
      </SortableZone>
      <span className={s.newViewReveal}>{newViewButton}</span>
    </>
  )

  return (
    <ViewEmbedScopeProvider
      value={{
        source,
        view,
        persistConfig: (next) => persistConfig(index, next),
        locked,
        setLocked,
      }}
    >
      <div className={s.tile} onPointerDownCapture={onActivate}>
        {titleShown && (
          // biome-ignore lint/a11y/noStaticElementInteractions: right-click chrome menu on the title row.
          <div className={s.titleRow} onContextMenu={(e) => void titleMenu(e)}>
            {/* size omitted → Icon defaults to 1em; the .md-hN class sets the em base, so the icon
                scales with the title level in lockstep with the text. */}
            {iconShown && <Icon name={viewIcon(view)} className={`md-h${titleLevel}`} />}
            <EmbedTitle
              title={entry.display_title ?? source.title}
              level={titleLevel}
              onCommit={commitTitle}
            />
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
        <div className={`${s.body} edge-fade`}>
          <div
            key={index}
            className={s.slideWrap}
            style={{ '--slide-from': slideFrom } as React.CSSProperties}
          >
            <ViewRenderer key={source.id} source={source} />
          </div>
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
              footer={<MenuBottomRow leading={newViewButton} />}
            >
              <Menu>
                {views.map((v, i) => (
                  <MenuItem
                    key={v.id}
                    className={i === index ? activeRow : undefined}
                    leading={<Icon name={viewIcon(v)} size={16} />}
                    onClick={renaming === i ? undefined : () => patchEntry({ active: i })}
                    onContextMenu={(e) => void rowMenu(i, e, false)}
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
