import type { NexusTree } from '@shared/types'
import { BlockSurface } from '@renderer/Blocks/BlockSurface'
import { DetailScaffold } from './DetailScaffold'

// Module-level: a fresh literal per render would churn every tile memo downstream.
const HOMEPAGE_HOST = { kind: 'homepage' } as const

/**
 * The homepage view — the live nexus entity (the sidebar header), hosting the real
 * block surface persisted to homepage.json (the G-12 dev host; removable behind the
 * BlockHost seam). The SurfacePM lab stays reachable from the showcase leaf.
 */
export function HomepageView({ tree }: { tree: NexusTree | null }): React.JSX.Element {
  return (
    <DetailScaffold owner={{ path: '', kind: 'homepage', name: tree?.nexus.name ?? 'Home', banner: tree?.homepage.banner }}>
      <BlockSurface host={HOMEPAGE_HOST} />
    </DetailScaffold>
  )
}
