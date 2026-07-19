## CardView

The Cards renderer draws a [Collection's](Collections.md) (or a depth-1 Set's) Pages as a resizable card grid, over the same pure pipeline that feeds the [Table](TableView.md) — columns → filter → group → sort. It's the first of the non-Table renderers; a Collection or Set switches to it from the ViewSettings type grid, and it renders identically inside a [view embed](SurfacePM.md).

### Features

#### II. Card Anatomy & Sizing

A page card is an image band over a text area (title, then properties, then an optional location footing). The image band is a fixed height scaled by the card factor; the text extends below, and every card in a grid row matches its tallest sibling (shorter cards top-align). The grid is an auto-fill track set off a column-width floor, so a partly-filled band keeps the same card size as a full one rather than ballooning. The card chassis — grid mechanics, aspect, non-image borders, container-query title type, and the hover-pop — is shared with the [Navigation](Navigation.md) gallery card; the inner title/property area is the cards renderer's own.

**Scale** is a slider in the ViewSettings footing (the design-system Slider — an accent-over-track fill with the shared glass knob), drafting live while dragging and writing the view on release; the scrub is scoped per view so a sibling cards embed on the same surface isn't dragged along. The scale factor persists as `card_size` (a number; legacy small/medium/large names map to a factor on read, and a non-finite value is rejected to the default).

#### II. Card Image

A per-view **Card Banner** control chooses the image source: **Cover** (the page's `cover` banner), **Preview** (the captured page thumbnail, the nav gallery's pipeline), or **None** (imageless, compact cards — the band rhythm tightens with them). A page lacking an image under Cover/Preview shows the placeholder, so heights stay uniform within a view. No new attach flow exists — the banner set/crop/write already ships. The Preview thumbnail rides the one shared, persistent thumbnail cache.

#### II. Layouts

Card layout is the view's `format`, per-renderer in meaning (Table: density; Cards: layout):

- **Standard** — the title, then one labeled row per visible property: label left, value right.
- **Compact** — the title, then label-less values flowing in property order, tightly packed, never wrapping.

Two LayoutPane switches shape them further: **Wrap Titles** (on lets the title wrap; off keeps it single-line via the shared overflow-scroll) and **Hide Icons**. A value never wraps in either layout — chips keep their hover-scroll mechanics, text-shaped values clamp.

#### II. Properties on Cards

Cards show every visible property (the view's `property_order` minus `hidden_properties`), rendered through the shared chip/cell renderers. Each value is interactive on the ratified per-kind gesture matrix (the same surface the table cells use): a click opens the value's picker — status/select/multi/context/tier open the dropdown, a checkbox toggles, a date opens the calendar, a number/url opens the inline editor. A right-click opens the value's native menu (Clear · Style · Edit) off the shared cell-menu model. Because the whole card is a drag handle, each interactive value stops the drag's pointer capture so its click survives; the card still drags from its thumb and title.

Adding a value comes from the **two-stage add-picker** (G-1): a property list that slides into the picked property's value pane — status/select/multi-select/context author their chip pane; date, number, and url slide to their editor; a checkbox commits straight from the list. The property list groups the pane-bearing pickers to the top and the simpler kinds below, preserving property order within each group. The add-picker opens from a Compact card's empty flow space, from a card's location footing, or from the native card menu's **Add Property ▸** submenu (the add path when a card has no in-body surface).

#### II. Grouping, Location & Sorting

Cards never indent: structural (location) grouping renders a flat disclosure band per top-level Set, its whole subtree's pages rolled up under it; sub-set nesting never indents a card. A property group replaces the location bands with bucket bands. Ungrouped/root pages band under the container's own heading rather than a header-less tail. Band chrome is collapse (persisted) plus a hover **"+"** on structural bands only (inert until the creation-affordance design lands). No sub-grouping and no heading columns apply.

**Sort by Location** (a Sorting-pane switch, not a sort criterion) flattens the structural bands into one headerless, location-ordered list — the sorter still ranks within it. It forces structural resolution (mutually exclusive with a property group, which it overrides), forces the single band open, shows each card's full location footing, and disables drag (the order is computed).

Each card's **location footing** is a Set / sub-Set breadcrumb governed by a standing **Hide Location** switch, independent of grouping mode. Under structural grouping the band header already names the top-level Set, so the footing drops that leading crumb; in the flattened Sort-by-Location list (no header) it shows the full chain.

#### II. Set Cards

A **Set Cards** switch adds a leading row of larger cards, one per Set (or per depth-1 sub-Set in a Set view) — banner (placeholder when unset) + icon + title. Clicking a Set Card navigates to the Set; the Cards row is reorderable by drag (writing the container's set order). A container with no Sets shows no row; an empty Set still gets its card.

#### II. Card Drag & Menus

Cards reorder within their band by displacement (the nav gallery's drag), writing the per-machine manual order the pipeline reads as its lowest-priority sort tiebreaker; two effective sort criteria retire the drag, and the flattened Sort-by-Location mode disables it. Cross-band drops are a follow-up.

A card's **right-click** opens a native menu: Open · Rename · Change Icon · Delete, plus the Add Property ▸ submenu — Rename mounts the shared text picker, Change Icon the icon picker. A value's own right-click menu takes precedence over the card menu.

#### II. Surfaces & Insets

Cards live in the ViewSettings type grid (activated alongside Table) and carry their options in the Layout leaf: the Card Banner picker, the Hide Location / Wrap Titles / Hide Icons / Set Cards switches, with Style (the two-option flip toggle) and Scale pinned in the footing. The grouping and sorting leaves reuse the shared panes. A view switched to a type inherits the new type's default glyph only when it still wore the old default. Cards ride the block-surface inset regime (no view gutter), chosen by a pane-body rule so the view itself never pads.

### Pending

- **Compact styling** — the Compact layout's flow packing and imageless-card rhythm are a build-then-sign-off pass.
- **Heading "+" creation** — the structural-band "+" is visual only until the page-creation affordance is designed.

### Prospects

- **Set-Card view previews** — a Set Card opening a preview of the Set's view (needs preview-views); v1 navigates.
- **File-property covers** — any File property declaring itself the card's image (needs a nexus-root read scope + an attach picker); the Card Banner mode set is extensible for a fourth "Property" mode.
- **Fit Image / Reposition** — contain-vs-fill and hover-reposition on covers; v1 is fill-crop.
- **Cross-group card drag** — a card dropped into another location or property band as a real move / property write.
- **Fuller band chrome** — band drag, a native band-header menu, and inline band rename (table territory today).
