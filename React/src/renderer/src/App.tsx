import { useEffect } from 'react'
import { useSession } from './store'
import { Surface } from './components/Surface'
import { Sidebar } from './components/Sidebar'
import { DetailPane } from './components/DetailPane'

export function App(): React.JSX.Element {
  const { status, tree, error, load } = useSession()

  useEffect(() => {
    void load()
  }, [load])

  return (
    <div className="shell">
      <main className="content-pane">
        <DetailPane />
      </main>
      <Surface>
        {status === 'loading' && <div className="state">Loading nexus…</div>}
        {status === 'error' && (
          <div className="state state-error">
            Couldn’t open nexus
            <span className="state-detail">{error}</span>
          </div>
        )}
        {status === 'ready' && tree && <Sidebar tree={tree} />}
      </Surface>
    </div>
  )
}
