import { useEffect, useRef, useState } from 'react'
import { useSession } from '../store'
import { duration, easing } from '@renderer/design-system/tokens'
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
// KNOB — how far the incoming view slides in on a directional navigation (tab switch / Back / Forward).
const VIEW_SLIDE_PX = 14

// The preview's engulf target (A-4): the detail pane's live rect, read once at promote time —
// module-held so the floating window needs no prop threading across trees.
let paneEl: HTMLElement | null = null
export const getDetailPaneRect = (): DOMRect | null => paneEl?.getBoundingClientRect() ?? null

export function DetailPane(): React.JSX.Element {
  const selection = useSession((s) => s.selection)
  const selectionKind = selection.kind
  // Cold-switch pause: the outgoing view holds as its last frame, input-frozen, until the incoming
  // page's fetch lands (or the deadline drops to the loading view) — see store.select's page case.
  const frozen = useSession((s) => s.pageFrozen)
  const navSlide = useSession((s) => s.navSlide)
  const expanded = useSession((s) => s.subfieldExpanded)
  const setExpanded = useSession((s) => s.setSubfieldExpanded)

  // Directional view slide: when a stamped navigation's swap COMMITS (selection changes with an
  // unconsumed stamp — under the pause that's one commit, possibly later than the stamp), the incoming
  // view slides in from the step's direction. WAAPI on the wrapper: nothing remounts, replays per seq,
  // and a plain sidebar select (no stamp) swaps without motion.
  const viewRef = useRef<HTMLDivElement>(null)
  const prevSelection = useRef(selection)
  const playedSeq = useRef(0)
  useEffect(() => {
    const swapped = prevSelection.current !== selection
    prevSelection.current = selection
    if (!swapped || !navSlide || navSlide.seq === playedSeq.current) return
    playedSeq.current = navSlide.seq
    const x = navSlide.dir === 'back' ? -VIEW_SLIDE_PX : VIEW_SLIDE_PX
    viewRef.current?.animate(
      [
        { transform: `translateX(${x}px)`, opacity: 0 },
        { transform: 'translateX(0)', opacity: 1 },
      ],
      { duration: Number.parseInt(duration.fast, 10), easing: easing.standard },
    )
  }, [selection, navSlide])
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
      ref={(el) => {
        paneEl = el
      }}
      onMouseMove={(e) => {
        if (!showSubfield) return
        const r = e.currentTarget.getBoundingClientRect()
        setNear(e.clientX > r.right - 260 && e.clientY > r.bottom - 120)
      }}
      onMouseLeave={() => setNear(false)}
    >
      <div ref={viewRef} className={frozen ? 'detail-pane-view is-frozen' : 'detail-pane-view'}>
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
