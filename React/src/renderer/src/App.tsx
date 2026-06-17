import { useEffect } from 'react'
import { useSession } from './store'
import { Surface } from './components/Surface'
import { Sidebar } from './components/Sidebar'
import { DetailPane } from './components/DetailPane'

export function App(): React.JSX.Element {
  const { status, tree, error, sidebarVisible, load, choose, openDropped, toggleSidebar, newPage, beginRename } =
    useSession()

  useEffect(() => {
    void load()
  }, [load])

  // Context-menu "Rename" → main signals the renderer to inline-edit the row at this path.
  useEffect(() => {
    return window.nexus.onBeginRename((path) => beginRename(path))
  }, [beginRename])

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
      className={'shell' + (sidebarHidden ? ' sidebar-hidden' : '')}
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
      {!sidebarHidden && (
        <Surface>
          {status === 'loading' && <div className="state">Loading Nexus…</div>}
          {status === 'empty' && (
            <div className="state">
              No nexus open
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
      )}
    </div>
  )
}
