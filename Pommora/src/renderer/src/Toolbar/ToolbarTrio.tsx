import {
  SegmentedSymbol,
  type Segment,
} from '@renderer/design-system/components/Segmented-Controls'

/**
 * The trailing Navigation · Settings · Inspector trio. The glass pill is a SEPARATE in-flow layer from
 * the live buttons so it can fade out ("void") on its own as the inspector swallows the trio — leaving
 * the icons riding on the inspector's glass with no double-glass. The fade + ride are driven by --io
 * (toolbar.css).
 *
 * The glass layer is in-flow (so the liquid glass measures + clips crisply — absolute renders soft) and
 * sizes the cluster; the live bare buttons overlay it. `inert` + `aria-hidden` keep the glass layer's
 * duplicate buttons decorative. Note: editing this re-inits liquid glass, so dev hot-reload shows a
 * broken frame until a full reload — cold loads + the production build are clean.
 */
export function ToolbarTrio({ segments }: { segments: Segment[] }): React.JSX.Element {
  return (
    <div className="toolbar-trio">
      <div className="toolbar-trio-glass" aria-hidden inert>
        <SegmentedSymbol segments={segments} />
      </div>
      <div className="toolbar-trio-cover">
        <SegmentedSymbol segments={segments} glass={false} />
      </div>
    </div>
  )
}
