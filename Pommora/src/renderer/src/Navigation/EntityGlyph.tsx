import { Icon } from '@renderer/design-system/symbols'
import { cx } from '@renderer/design-system/cx'
import { assetUrl } from '../assetUrl'
import { useSession } from '../store'
import type { ResolvedNav } from './navResolve'
import './entityGlyph.css'

// A nav entity's leading glyph. The Homepage is the nexus itself — when a nexus photo is set it shows
// as a round avatar (its identity), matching the sidebar; otherwise (and for every other kind) the
// resolved icon glyph.
export function EntityGlyph({
  item,
  size,
  className,
}: {
  item: ResolvedNav
  size: number
  className?: string
}): React.JSX.Element {
  const profileImage = useSession((s) => s.tree?.nexus.profileImage ?? null)
  if (item.kind === 'homepage' && profileImage) {
    return (
      <img
        className={cx('entity-glyph-photo', className)}
        style={{ width: size, height: size }}
        src={assetUrl(profileImage)}
        alt=""
      />
    )
  }
  return <Icon name={item.icon} size={size} className={className} />
}
