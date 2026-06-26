import { Icon } from '@renderer/design-system/symbols'

/**
 * The canonical hover-revealed "Add Banner" affordance — icon + label, used by every banner-less
 * header (container/context views via Banner, the page editor via PageHeader). One markup + one CSS
 * source (`add-banner-strip` / `add-banner-btn` in Banner.css); consumers supply only the click
 * handler. The strip is the hover zone; the button fades in on hover and triggers the picker.
 */
export function AddBannerButton({ onClick }: { onClick: () => void }): React.JSX.Element {
  return (
    <div className="add-banner-strip">
      <button
        type="button"
        className="add-banner-btn"
        onClick={onClick}
        aria-label="Add banner"
        title="Add a banner"
      >
        <Icon name="square-plus" size={14} />
        Add Banner
      </button>
    </div>
  )
}
