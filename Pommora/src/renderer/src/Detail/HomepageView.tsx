import type { NexusTree } from '@shared/types'
import { SurfaceLab } from '@renderer/SurfacePM/SurfaceLab'
import { DetailScaffold } from './DetailScaffold'

/**
 * The homepage view — the live nexus entity (the sidebar header). Currently hosts the
 * SurfacePM lab (dummy tiles over the live tessellation engine) as its dev proving
 * ground; the real block surface replaces the lab when tile content lands.
 */
export function HomepageView({ tree }: { tree: NexusTree | null }): React.JSX.Element {
  return (
    <DetailScaffold owner={{ path: '', kind: 'homepage', name: tree?.nexus.name ?? 'Home', banner: tree?.homepage.banner }}>
      <SurfaceLab />
    </DetailScaffold>
  )
}
