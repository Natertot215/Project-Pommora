import { useState } from 'react'
import { useSession } from '../store'
import { Icon } from '@renderer/design-system/symbols'
import { findCollection, findSet } from './Scope'
import { ContainerView } from './ContainerView'
import { HomepageView } from './HomepageView'
import { ContextView } from './ContextView'
import { PageView } from './PageView'
import { NavView } from '../Tabs/NavView'
import { Subfield } from './Subfield/Subfield'

/**
 * Routes the current selection to its view. Collection + (depth-1) Set share ContainerView (same
 * view principles); Homepage and Context have their own; Page is a placeholder. (Swift: SidebarDetailView.)
 */
function DetailView(): React.JSX.Element {
  const selection = useSession((s) => s.selection)
  const tree = useSession((s) => s.tree)

  switch (selection.kind) {
    case 'none':
      // The empty state IS NavView (E-2) — a NavView tab routes here via `selection: none`. With no
      // nexus open there's nothing to browse, so the pane stays blank (App shows the open prompt).
      return tree ? (
        <NavView />
      ) : (
        <div className="detail detail-empty">
          <span>Select a collection or page</span>
        </div>
      )
    case 'homepage':
      return <HomepageView tree={tree} />
    case 'context':
      return <ContextView tree={tree} id={selection.id} />
    case 'collection': {
      const col = findCollection(tree, selection.id)
      return col ? (
        <ContainerView source={col} />
      ) : (
        <div className="detail">
          <div className="detail-placeholder">Collection not found</div>
        </div>
      )
    }
    case 'set': {
      const set = findSet(tree, selection.id)
      return set ? (
        <ContainerView source={set} />
      ) : (
        <div className="detail">
          <div className="detail-placeholder">Set not found</div>
        </div>
      )
    }
    case 'page':
      return (
        <div className="detail detail-page">
          <PageView />
        </div>
      )
  }
}

/**
 * The detail pane: the routed view above, the Subfield (footer) pinned below. The Subfield collapses
 * app-wide via a hover chevron — `.subfield-reveal` slides it up/down and reclaims its space.
 */
export function DetailPane(): React.JSX.Element {
  const selectionKind = useSession((s) => s.selection.kind)
  const expanded = useSession((s) => s.subfieldExpanded)
  const setExpanded = useSession((s) => s.setSubfieldExpanded)
  // Cursor in the chevron's general area (a large bottom-right region) → reveal the toggle. Tracked
  // here rather than with a giant invisible button so the reveal zone never blocks clicks beneath it.
  const [near, setNear] = useState(false)

  // The Subfield shows only where it has something to display: Collections, Sets, and Pages.
  // Contexts + Homepage are omitted — there's nothing to display here anyway; put it back when
  // there's actually stuff to show.
  const showSubfield =
    selectionKind === 'collection' || selectionKind === 'set' || selectionKind === 'page'

  const paneClass =
    'detail-pane' +
    (showSubfield && expanded ? ' subfield-open' : '') +
    (showSubfield && near ? ' subfield-near' : '')

  return (
    <div
      className={paneClass}
      onMouseMove={(e) => {
        if (!showSubfield) return
        const r = e.currentTarget.getBoundingClientRect()
        setNear(e.clientX > r.right - 260 && e.clientY > r.bottom - 120)
      }}
      onMouseLeave={() => setNear(false)}
    >
      <div className="detail-pane-view">
        <DetailView />
      </div>
      {showSubfield && (
        <>
          <button
            type="button"
            className="subfield-toggle"
            onClick={() => setExpanded(!expanded)}
            aria-label={expanded ? 'Hide footer' : 'Show footer'}
            title={expanded ? 'Hide footer' : 'Show footer'}
          >
            <Icon name={expanded ? 'chevron-down' : 'chevron-up'} size="md" />
          </button>
          <div className="subfield-reveal">
            <Subfield />
          </div>
        </>
      )}
    </div>
  )
}
