import {
  useEffect,
  useRef,
  useState,
  type CSSProperties,
  type PointerEvent as ReactPointerEvent,
} from 'react'
import { useSession } from './store'
import { Surface } from './Components/Surface'
import { Sidebar } from './Sidebar/Sidebar'
import { Ribbon } from './Sidebar/Ribbon'
import { DetailPane } from './Detail/DetailPane'
import { Toolbar } from './Toolbar/Toolbar'
import { InspectorPanel } from './Detail/InspectorPanel/InspectorPanel'
import { NavWindow } from './NavWindow/NavWindow'
import { PreviewWindow } from './PagePreview/PreviewWindow'
import { contextTargetToSelect } from './Tabs/tabsModel'
import { useNavThumbnails } from './Navigation/useNavThumbnails'
import { Icon } from '@renderer/design-system/symbols'
import { matchesCommand } from './Commands'

export function App(): React.JSX.Element {
  // Per-field selectors, never the bare hook: the shell must not re-render on every store set()
  // — only when a field it renders actually changes. Actions are stable references (defined
  // once at store creation), so selecting them individually is safe.
  const status = useSession((s) => s.status)
  const tree = useSession((s) => s.tree)
  const error = useSession((s) => s.error)
  const sidebarVisible = useSession((s) => s.sidebarVisible)
  const sidebarWidth = useSession((s) => s.sidebarWidth)
  const setSidebarWidth = useSession((s) => s.setSidebarWidth)
  const inspectorWidth = useSession((s) => s.inspectorWidth)
  const setInspectorWidth = useSession((s) => s.setInspectorWidth)
  const persistPaneWidths = useSession((s) => s.persistPaneWidths)
  const load = useSession((s) => s.load)
  const applyTree = useSession((s) => s.applyTree)
  const applyNavChanged = useSession((s) => s.applyNavChanged)
  const choose = useSession((s) => s.choose)
  const openDropped = useSession((s) => s.openDropped)
  const toggleSidebar = useSession((s) => s.toggleSidebar)
  const ribbonVisible = useSession((s) => s.ribbonVisible)
  const toggleRibbon = useSession((s) => s.toggleRibbon)
  const toggleNav = useSession((s) => s.toggleNav)
  const commands = useSession((s) => s.commands)
  const newPage = useSession((s) => s.newPage)
  const openNewTab = useSession((s) => s.openNewTab)
  const beginRename = useSession((s) => s.beginRename)
  const select = useSession((s) => s.select)
  useNavThumbnails() // capture-on-open detail-pane thumbnails for the gallery

  // Inspector toggle — window chrome state. Full-height pane that pushes content when open.
  const [inspectorOpen, setInspectorOpen] = useState(false)

  // Edge-drag resize (no visible handle). `resizing` suspends the collapse transition so
  // the panel tracks the cursor 1:1; the store clamps to the Swift min/max + persists.
  const [resizing, setResizing] = useState(false)
  const drag = useRef({ active: false, startX: 0, startW: 0 })
  const onResizeDown = (e: ReactPointerEvent<HTMLDivElement>): void => {
    drag.current = { active: true, startX: e.clientX, startW: sidebarWidth }
    e.currentTarget.setPointerCapture(e.pointerId)
    setResizing(true)
  }
  const onResizeMove = (e: ReactPointerEvent<HTMLDivElement>): void => {
    if (!drag.current.active) return
    setSidebarWidth(drag.current.startW + (e.clientX - drag.current.startX))
  }
  const onResizeUp = (): void => {
    drag.current.active = false
    setResizing(false)
    persistPaneWidths()
  }

  // Inspector edge-drag resize — mirror of the sidebar, but the left edge grows the pane
  // as it's dragged leftward (delta subtracted). Reuses `resizing` to suspend transitions.
  const inspectorDrag = useRef({ active: false, startX: 0, startW: 0 })
  const onInspectorResizeDown = (e: ReactPointerEvent<HTMLDivElement>): void => {
    inspectorDrag.current = { active: true, startX: e.clientX, startW: inspectorWidth }
    e.currentTarget.setPointerCapture(e.pointerId)
    setResizing(true)
  }
  const onInspectorResizeMove = (e: ReactPointerEvent<HTMLDivElement>): void => {
    if (!inspectorDrag.current.active) return
    setInspectorWidth(inspectorDrag.current.startW - (e.clientX - inspectorDrag.current.startX))
  }
  const onInspectorResizeUp = (): void => {
    inspectorDrag.current.active = false
    setResizing(false)
    persistPaneWidths()
  }

  useEffect(() => {
    void load()
  }, [load])

  // Context-menu "Rename" → main signals the renderer to inline-edit the row at this path.
  useEffect(() => {
    return window.nexus.onBeginRename((path) => beginRename(path))
  }, [beginRename])

  // Context-menu "Open in New Tab" → open into a new tab (dedup focuses an already-open one, I-1).
  useEffect(() => {
    return window.nexus.onOpenInNewTab((target) => {
      if (!target.id) return
      void select(contextTargetToSelect({ kind: target.kind, id: target.id, path: target.path }), {
        newTab: true,
      })
    })
  }, [select])

  // Context-menu "Open in Preview" (page rows) → the floating preview window.
  const openPreview = useSession((s) => s.openPreview)
  useEffect(() => {
    return window.nexus.onOpenInPreview((target) => {
      if (target.id) openPreview({ id: target.id, path: target.path })
    })
  }, [openPreview])

  // The live filesystem watcher pushed a fresh tree (external change) → swap it in place.
  // Single-window v1: main guards stale pushes by session root; on an in-window nexus
  // switch a rare in-flight push self-heals (the switch's own load() applies last).
  useEffect(() => {
    return window.nexus.onNexusChanged((next) => void applyTree(next))
  }, [applyTree])

  // A synced-in Nav sidecar / pin change (from another machine) → refresh nav state only, no tree walk.
  useEffect(() => {
    return window.nexus.onNavChanged((nav) => applyNavChanged(nav))
  }, [applyNavChanged])

  // Native-menu actions reuse the store's existing behaviors (the menu is a second
  // trigger, not a second implementation).
  useEffect(() => {
    return window.nexus.onMenuAction((action) => {
      switch (action) {
        case 'open':
          void choose()
          break
        case 'new-tab': {
          // I-20: ⌘N is a NATIVE accelerator (menu.ts) — a renderer keydown can't intercept it, so
          // the promote branch lives here. While a page-flavor preview is open, its active tab
          // promotes to a new app tab and closes (the window only when it was the last).
          const s = useSession.getState()
          const p = s.preview
          const active =
            p?.flavor === 'page' ? p.tabs.find((t) => t.id === p.activeTabId) : undefined
          if (active && active.target.kind === 'page') {
            void s.select(
              { kind: 'page', id: active.target.id, path: active.target.path },
              { newTab: true },
            )
            s.closePreviewTab(active.id, 'engulf')
          } else openNewTab()
          break
        }
        case 'new-page':
          void newPage()
          break
        case 'toggle-sidebar':
          toggleSidebar()
          break
        case 'reload-state':
          void load()
          break
      }
    })
  }, [choose, newPage, openNewTab, toggleSidebar, load])

  // Nexus-bound keyboard commands (settings.json `commands`) — window chrome shortcuts.
  useEffect(() => {
    const onKey = (e: KeyboardEvent): void => {
      // A focused surface that claimed the chord keeps it (the editor's Mod-e = inline code).
      if (e.defaultPrevented) return
      if (matchesCommand(commands['toggle-ribbon'], e)) {
        e.preventDefault()
        toggleRibbon()
      } else if (matchesCommand(commands['toggle-nav'], e)) {
        e.preventDefault()
        toggleNav()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [commands, toggleRibbon, toggleNav])

  // The sidebar only "hides" when a nexus is open (its content is the tree). With
  // nothing open, the panel is the Open-Folder prompt — keep it visible so toggling
  // off an empty window can't strand the user with no on-screen affordance.
  const sidebarHidden = status === 'ready' && !sidebarVisible

  return (
    <div
      className={
        'shell' +
        (sidebarHidden ? ' sidebar-hidden' : '') +
        (ribbonVisible ? '' : ' ribbon-hidden') +
        (inspectorOpen ? ' inspector-open' : '') +
        (resizing ? ' is-resizing' : '')
      }
      style={
        {
          '--sidebar-width': `${sidebarWidth}px`,
          '--inspector-width': `${inspectorWidth}px`,
        } as CSSProperties
      }
      onDragOver={(e) => e.preventDefault()}
      onDrop={(e) => {
        e.preventDefault()
        const file = e.dataTransfer.files[0]
        if (file) void openDropped(file)
      }}
    >
      {/* Draggable top strip so the frameless window can be moved from anywhere along the top. */}
      <div className="titlebar" />
      {/* Persistent toolbar clusters float over the strip (Back/Forward + Navigation·Settings·Inspector). */}
      {status === 'ready' && (
        <Toolbar
          inspectorOpen={inspectorOpen}
          onToggleInspector={() => setInspectorOpen((v) => !v)}
        />
      )}
      <main className="content-pane">
        <DetailPane />
      </main>
      {/* Sidebar always mounted so collapse/expand animates (slides) instead of snapping;
          .shell.sidebar-hidden translates it off + reclaims the detail gutter. */}
      <Surface>
        {/* Ribbon: a pinned icon strip left of the scrolling sidebar; switches sidebar modes. */}
        {status === 'ready' && tree && <Ribbon />}
        {/* Collapse — in-line with the traffic lights (sidebar top-right); reveals on hover. */}
        <button
          type="button"
          className="sidebar-toggle sidebar-collapse"
          onClick={toggleSidebar}
          aria-label="Collapse sidebar"
          title="Collapse sidebar"
        >
          <Icon name="log-out" size={18} className="flip-x" />
        </button>
        {status === 'loading' && <div className="state">Loading Nexus…</div>}
        {status === 'empty' && (
          <div className="state">
            No Nexus Open
            <button className="open-btn" onClick={() => void choose()}>
              Open Folder…
            </button>
          </div>
        )}
        {status === 'error' && (
          <div className="state state-error">
            Couldn’t Open Nexus
            <span className="state-detail">{error}</span>
          </div>
        )}
        {status === 'ready' && tree && <Sidebar tree={tree} />}
      </Surface>
      {/* Drag strip over the sidebar's top band — a child of the frosted Surface can't carry a drag
          region (its backdrop-filter layer swallows it), and draggable regions resolve in PAINT order
          (the sidebar's no-drag content punches any earlier drag region), so the handle lives at shell
          level AFTER the Surface. Clears the collapse toggle; retracts when the sidebar hides. */}
      {status === 'ready' && !sidebarHidden && <div className="sidebar-titlebar" />}
      {/* Invisible edge-drag resize strip at the sidebar's right edge (only while expanded). */}
      {!sidebarHidden && (
        <div
          className="sidebar-resize"
          onPointerDown={onResizeDown}
          onPointerMove={onResizeMove}
          onPointerUp={onResizeUp}
          onPointerCancel={onResizeUp}
          onLostPointerCapture={onResizeUp}
          role="separator"
          aria-orientation="vertical"
          aria-label="Resize sidebar"
        />
      )}
      {/* Expand — always mounted at the top-left toggle spot, layered on top. Hidden behind
          the open sidebar's collapse button; revealed (fade + ease) as the sidebar slides off,
          and overtaken as it slides back. Always mounted so there's no in/out snap. */}
      <button
        type="button"
        className="sidebar-toggle sidebar-expand"
        onClick={toggleSidebar}
        aria-label="Show sidebar"
        title="Show sidebar"
      >
        <Icon name="log-out" size={18} />
      </button>
      {/* Trailing inspector pane — full-height twin of the sidebar; pushes content when open. */}
      {status === 'ready' && <InspectorPanel open={inspectorOpen} />}
      {/* NavWindow — the ribbon/⌘O-summoned floating mini-shell; app-global overlay, own presence. */}
      {status === 'ready' && <NavWindow />}
      {/* Page Preview — the B-1-routed floating page window; one floating window total (D-8). */}
      {status === 'ready' && <PreviewWindow />}
      {/* Invisible edge-drag resize strip at the inspector's left edge (only while open). */}
      {status === 'ready' && inspectorOpen && (
        <div
          className="inspector-resize"
          onPointerDown={onInspectorResizeDown}
          onPointerMove={onInspectorResizeMove}
          onPointerUp={onInspectorResizeUp}
          onPointerCancel={onInspectorResizeUp}
          onLostPointerCapture={onInspectorResizeUp}
          role="separator"
          aria-orientation="vertical"
          aria-label="Resize inspector"
        />
      )}
    </div>
  )
}
