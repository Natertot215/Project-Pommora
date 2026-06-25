import type { NexusTree } from '@shared/types'
import { DetailScaffold } from './DetailScaffold'
import { findContext } from './Scope'

/**
 * A selected context (Area / Topic / Project) — a blank page under its banner; live block-pages
 * are future work. (Swift: ContextDetailPlaceholder.)
 */
export function ContextView({ tree, id }: { tree: NexusTree | null; id: string }): React.JSX.Element {
  return <DetailScaffold owner={findContext(tree, id)} lockedHeader />
}
