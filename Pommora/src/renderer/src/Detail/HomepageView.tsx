import type { NexusTree } from '@shared/types'
import { DetailScaffold } from './DetailScaffold'

/**
 * The homepage view — the live nexus entity (the sidebar header). v1 renders a blank page under
 * its banner; dynamic widgets are future work, composed here at the view level (not the banner's).
 */
export function HomepageView({ tree }: { tree: NexusTree | null }): React.JSX.Element {
  return <DetailScaffold owner={{ path: '', kind: 'homepage', name: tree?.nexus.name ?? 'Home', banner: tree?.homepage.banner }} />
}
