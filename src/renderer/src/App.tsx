import { useEffect } from 'react'
import { useSession } from './store'
import { Surface } from './components/Surface'
import { Sidebar } from './components/Sidebar'

export function App(): React.JSX.Element {
  const { status, tree, error, load } = useSession()

  useEffect(() => {
    void load()
  }, [load])

  return (
    <div className="shell">
      <Surface className="sidebar-pane">
        {status === 'loading' && <div className="state">Loading nexus…</div>}
        {status === 'error' && (
          <div className="state state-error">
            Couldn’t open nexus
            <span className="state-detail">{error}</span>
          </div>
        )}
        {status === 'ready' && tree && <Sidebar tree={tree} />}
      </Surface>
      <main className="content-pane" />
    </div>
  )
}
