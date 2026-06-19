import { useEffect, useRef, useState, type CSSProperties, type PointerEvent as ReactPointerEvent } from 'react'
import { useSession } from './store'
import { Surface } from './components/Surface'
import { Sidebar } from './components/Sidebar'
import { DetailPane } from './components/DetailPane'
import { Icon } from '@renderer/design-system/symbols'

export function App(): React.JSX.Element {
  const { status, tree, error, sidebarVisible, sidebarWidth, setSidebarWidth, load, applyTree, choose, openDropped, toggleSidebar, newPage, beginRename } =
    useSession()

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
  }

  useEffect(() => {
    void load()
  }, [load])

  // Context-menu "Rename" → main signals the renderer to inline-edit the row at this path.
  useEffect(() => {
    return window.nexus.onBeginRename((path) => beginRename(path))
  }, [beginRename])

  // The live filesystem watcher pushed a fresh tree (external change) → swap it in place.
  // Single-window v1: main guards stale pushes by session root; on an in-window nexus
  // switch a rare in-flight push self-heals (the switch's own load() applies last).
  useEffect(() => {
    return window.nexus.onNexusChanged((next) => void applyTree(next))
  }, [applyTree])

  // Native-menu actions reuse the store's existing behaviors (the menu is a second
  // trigger, not a second implementation).
  useEffect(() => {
    return window.nexus.onMenuAction((action) => {
      switch (action) {
        case 'open':
          void choose()
          break
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
  }, [choose, newPage, toggleSidebar, load])

  // The sidebar only "hides" when a nexus is open (its content is the tree). With
  // nothing open, the panel is the Open-Folder prompt — keep it visible so toggling
  // off an empty window can't strand the user with no on-screen affordance.
  const sidebarHidden = status === 'ready' && !sidebarVisible

  return (
    <div
      className={'shell' + (sidebarHidden ? ' sidebar-hidden' : '') + (resizing ? ' is-resizing' : '')}
      style={{ '--sidebar-width': `${sidebarWidth}px` } as CSSProperties}
      onDragOver={(e) => e.preventDefault()}
      onDrop={(e) => {
        e.preventDefault()
        const file = e.dataTransfer.files[0]
        if (file) void openDropped(file)
      }}
    >
      {/* Draggable top strip so the frameless window can be moved from anywhere along the top. */}
      <div className="titlebar" />
      <main className="content-pane">
        <DetailPane />
      </main>
      {/* Sidebar always mounted so collapse/expand animates (slides) instead of snapping;
          .shell.sidebar-hidden translates it off + reclaims the detail gutter. */}
      <Surface>
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
      {/* Invisible edge-drag resize strip at the sidebar's right edge (only while expanded). */}
      {!sidebarHidden && (
        <div
          className="sidebar-resize"
          onPointerDown={onResizeDown}
          onPointerMove={onResizeMove}
          onPointerUp={onResizeUp}
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
    </div>
  )
}
