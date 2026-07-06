import { useLayoutEffect, useRef, useState } from 'react'
import type { CollectionNode, SetNode } from '@shared/types'
import { SegmentedSymbol, SegmentedButton, type Segment } from '@renderer/design-system/components/Segmented-Controls'
import { useDismiss } from '@renderer/design-system/components/Popover'
import { MenuSurface } from '@renderer/design-system/components/menu'
import { iconNameOr } from '@renderer/design-system/symbols'
import { useExitPresence } from '@renderer/design-system/useExitPresence'
import { useSession } from '../store'
import { findCollection, findSet, findCollectionForSet } from '../Detail/Scope'
import { useActiveView } from '../Detail/Views/useActiveView'
import { ViewPane } from './ViewPane'
import * as s from './viewDropdown.css'

/**
 * The per-container view switcher, standalone left of the toolbar trio. Renders only on a
 * Collection / depth-1 Set (which owns saved views): its glyph is the active view's icon; clicking
 * opens the ViewPane; right-clicking opens the native presentation menu (Show/Hide Title · Style).
 * The `view_style` branch is a real seam — Toolbar mode reuses the dropdown button until ViewBar lands.
 */
export function ViewDropdown(): React.JSX.Element | null {
  const selection = useSession((st) => st.selection)
  const tree = useSession((st) => st.tree)
  const node =
    selection.kind === 'collection'
      ? findCollection(tree, selection.id)
      : selection.kind === 'set'
        ? findSet(tree, selection.id)
        : undefined
  if (!node) return null
  return <ViewDropdownInner key={node.id} node={node} />
}

function ViewDropdownInner({ node }: { node: CollectionNode | SetNode }): React.JSX.Element {
  const tree = useSession((st) => st.tree)
  const load = useSession((st) => st.load)
  const [open, setOpen] = useState(false)
  const wrapRef = useRef<HTMLDivElement>(null)
  useDismiss(wrapRef, () => setOpen(false), open)
  const paneP = useExitPresence(open)
  // The pane is right-aligned to the button, so aim its notch at the button's centre (half the button
  // width in from the pane's right edge). The absolute pane doesn't affect the wrapper's in-flow width.
  const [btnW, setBtnW] = useState(0)
  const labeled = (node.viewButton ?? 'icon') === 'labeled'
  useLayoutEffect(() => {
    if (wrapRef.current) setBtnW(wrapRef.current.offsetWidth)
  }, [labeled])

  const schema =
    node.kind === 'collection' ? (node.properties ?? []) : (findCollectionForSet(tree, node.id)?.properties ?? [])
  const { view } = useActiveView(node, schema)

  const onContextMenu = async (e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    const action = await window.nexus.viewButtonMenu({
      viewButton: node.viewButton ?? 'icon',
      viewStyle: node.viewStyle ?? 'dropdown'
    })
    if (!action) return
    const patch =
      action === 'toggle-title'
        ? { view_button: labeled ? ('icon' as const) : ('labeled' as const) }
        : action === 'style-dropdown'
          ? { view_style: 'dropdown' as const }
          : { view_style: 'toolbar' as const }
    await window.nexus.container.configure(node.path, node.kind, patch)
    await load()
  }

  const segment: Segment = {
    icon: iconNameOr(view.icon, 'table'),
    title: 'Views',
    active: open,
    onClick: () => setOpen((o) => !o)
  }

  return (
    // biome-ignore lint/a11y/noStaticElementInteractions: onContextMenu targets the button chrome, whose
    // interactive control is the Segmented button inside.
    <div ref={wrapRef} className={s.wrapper} onContextMenu={(e) => void onContextMenu(e)}>
      {labeled ? (
        <SegmentedButton segments={[{ ...segment, label: view.name }]} className={s.labeled} />
      ) : (
        <SegmentedSymbol segments={[segment]} className={s.iconPad} />
      )}
      {paneP.mounted && (
        <div className={s.anchor}>
          <MenuSurface closing={paneP.closing} notchInsetRight={btnW ? btnW / 2 : undefined}>
            <ViewPane node={node} schema={schema} onClose={() => setOpen(false)} />
          </MenuSurface>
        </div>
      )}
    </div>
  )
}
