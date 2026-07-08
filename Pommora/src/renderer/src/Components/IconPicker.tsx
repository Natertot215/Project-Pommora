import { type MouseEvent, type RefObject, useCallback, useLayoutEffect, useMemo, useState } from 'react'
import { useVirtualizer } from '@tanstack/react-virtual'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu/PickerMenu'
import { Icon } from '@renderer/design-system/symbols'
import { lucideGlyph, searchIcons, type IconEntry } from '@renderer/design-system/symbols/AllSymbols'
import { reorder, SortableZone, useDragItem } from '@renderer/design-system/interactions/drag'
import { useSession } from '@renderer/store'
import { cx } from '@renderer/design-system/cx'
import * as s from './iconPicker.css'

const CELL = 34
const ICON_SIZE = 18

interface Props {
  open: boolean
  onClose: () => void
  /** The element the beak points at. Omit ⇒ PickerMenu anchors to the picker's own mount point. */
  triggerRef?: RefObject<HTMLElement | null>
  /** The currently-set icon id — highlighted in the grid/favorites. */
  value?: string
  /** Fires with the picked Lucide id; the pane then retracts. */
  onSelect?: (id: string) => void
  direction?: 'down' | 'up' | 'left' | 'right'
}

/**
 * The icon picker: a beaked PickerMenu over a left-aligned search, a right-click Favorites strip, and
 * the full virtualized Lucide grid. Favorites persist to `personalization.favoriteIcons`; the
 * right-click Favorite menu is the native Electron menu. Selection fires `onSelect`, then the shell
 * retracts.
 */
export function IconPicker({ open, onClose, triggerRef, value, onSelect, direction = 'down' }: Props): React.JSX.Element | null {
  const favorites = useSession((st) => st.personalization.favoriteIcons)
  const setPersonalization = useSession((st) => st.setPersonalization)
  const favs = favorites ?? []

  const [query, setQuery] = useState('')
  const filtered = useMemo(() => searchIcons(query), [query])

  const pick = useCallback(
    (id: string) => {
      onSelect?.(id)
      onClose()
    },
    [onSelect, onClose]
  )

  const toggleFav = useCallback(
    (id: string) => {
      const next = favs.includes(id) ? favs.filter((f) => f !== id) : [...favs, id]
      setPersonalization('favoriteIcons', next.length ? next : undefined)
    },
    [favs, setPersonalization]
  )
  const reorderFavs = useCallback(
    (a: string, o: string) => {
      const next = reorder(
        favs.map((id) => ({ id })),
        a,
        o
      ).map((x) => x.id)
      setPersonalization('favoriteIcons', next)
    },
    [favs, setPersonalization]
  )

  // Right-click ⇒ the native Favorite/Remove menu (main-owned); the renderer applies the toggle.
  const openContext = useCallback(
    async (e: MouseEvent, id: string) => {
      e.preventDefault()
      const res = await window.nexus.iconFavoriteMenu(favs.includes(id))
      if (res === 'toggle') toggleFav(id)
    },
    [favs, toggleFav]
  )

  // Virtualized grid: rows of `cols`. Defaults to 6 (Nathan's target width) so icons ALWAYS render —
  // a live width measurement only *widens* it, never blanks the grid. `scrollEl` is a state-backed
  // callback ref so the virtualizer re-runs the moment the element mounts (else the grid stays empty
  // until the first re-render — e.g. a keystroke).
  const [scrollEl, setScrollEl] = useState<HTMLDivElement | null>(null)
  const [listEl, setListEl] = useState<HTMLDivElement | null>(null)
  const [cols, setCols] = useState(6)
  useLayoutEffect(() => {
    if (!open || !scrollEl) return
    const measure = (): void => {
      // clientWidth (layout box), NOT getBoundingClientRect — the latter includes the Bloom scale
      // transform, so mid-open it reads a shrunken width and undercounts the columns.
      const w = scrollEl.clientWidth
      if (w > 0) setCols(Math.max(1, Math.floor(w / CELL)))
    }
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(scrollEl)
    return () => ro.disconnect()
  }, [open, scrollEl])

  // The list sits below the (scrolling) favorites strip, so tell the virtualizer how far its top is
  // offset from the scroll container's top — the favorites + separator height. Re-measured when
  // favorites appear/disappear.
  const [scrollMargin, setScrollMargin] = useState(0)
  useLayoutEffect(() => {
    if (listEl) setScrollMargin(listEl.offsetTop)
  }, [listEl, favs.length, open])

  const rowCount = Math.ceil(filtered.length / cols)
  const rowVirt = useVirtualizer({
    count: rowCount,
    getScrollElement: () => scrollEl,
    estimateSize: () => CELL,
    overscan: 6,
    scrollMargin
  })

  const beak = { down: s.beakDown, up: s.beakUp, left: s.beakLeft, right: s.beakRight }[direction]

  return (
    <PickerMenu open={open} onDismiss={onClose} triggerRef={triggerRef} direction={direction} center notchHeight={7} bareSurface contentClassName={cx(s.content, beak)}>
      <input className={s.search} placeholder="Search" value={query} spellCheck={false} onChange={(e) => setQuery(e.target.value)} />
      {favs.length === 0 && <div className={s.separator} />}

      <div ref={setScrollEl} className={cx(s.grid, 'overflow-eclipse-y')}>
        {favs.length > 0 && (
          <div className={s.favorites}>
            <div className={cx(s.favScroll, 'overflow-eclipse')}>
              <SortableZone items={favs} layout="grid" onReorder={reorderFavs}>
                {favs.map((id) => (
                  <FavCell key={id} id={id} selected={id === value} onPick={pick} onContext={openContext} />
                ))}
              </SortableZone>
            </div>
          </div>
        )}

        <div ref={setListEl} className={s.list} style={{ height: rowVirt.getTotalSize() }}>
          {rowVirt.getVirtualItems().map((vr) => {
            const start = vr.index * cols
            return (
              <div key={vr.key} className={s.row} style={{ height: CELL, transform: `translateY(${vr.start - scrollMargin}px)` }}>
                {filtered.slice(start, start + cols).map((entry) => (
                  <GridCell key={entry.id} entry={entry} selected={entry.id === value} onPick={pick} onContext={openContext} />
                ))}
              </div>
            )
          })}
        </div>
      </div>
    </PickerMenu>
  )
}

function GridCell({
  entry,
  selected,
  onPick,
  onContext
}: {
  entry: IconEntry
  selected: boolean
  onPick: (id: string) => void
  onContext: (e: MouseEvent, id: string) => void
}): React.JSX.Element {
  const Glyph = entry.Glyph
  return (
    <button
      type="button"
      className={cx(s.cell, selected && s.cellSelected)}
      title={entry.id}
      onClick={() => onPick(entry.id)}
      onContextMenu={(e) => onContext(e, entry.id)}
    >
      <Glyph size={ICON_SIZE} />
    </button>
  )
}

function FavCell({
  id,
  selected,
  onPick,
  onContext
}: {
  id: string
  selected: boolean
  onPick: (id: string) => void
  onContext: (e: MouseEvent, id: string) => void
}): React.JSX.Element {
  const { setNodeRef, style, handle } = useDragItem(id)
  const Glyph = lucideGlyph(id)
  return (
    <button
      type="button"
      ref={setNodeRef}
      style={style}
      {...handle}
      className={cx(s.cell, selected && s.cellSelected)}
      title={id}
      onClick={() => onPick(id)}
      onContextMenu={(e) => onContext(e, id)}
    >
      {Glyph ? <Glyph size={ICON_SIZE} /> : <Icon name="square-dashed" size={ICON_SIZE} />}
    </button>
  )
}
