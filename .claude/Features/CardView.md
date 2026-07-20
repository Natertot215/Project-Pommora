## CardView

The Cards renderer draws a [Collection's](Collections.md) (or a depth-1 Set's) Pages as a resizable card grid, over the same pure pipeline that feeds the [Table](TableView.md) — columns → filter → group → sort. It's the first of the non-Table renderers; a Collection or Set switches to it from the ViewSettings type grid, and it renders identically inside a [view embed](SurfacePM.md).

### Features

#### II. Card Anatomy & Sizing

A page card is an image band over a text area (title, then properties, then an optional location footing). The image band is a fixed height scaled by the card factor; the text extends below, and every card in a grid row matches its tallest sibling (shorter cards top-align). The grid is an auto-fill track set off a column-width floor, so a partly-filled band keeps the same card size as a full one rather than ballooning. The card chassis — grid mechanics, aspect, non-image borders, and the hover-pop — is shared with the [Navigation](Navigation.md) gallery card; the inner title/property area is the cards renderer's own. Card and set titles read one shared type source (the body ramp, semibold), and the location breadcrumb is always seated as a footing — pinned to the card's bottom under a divider, whether or not properties sit above it.

**Scale** is a slider in the ViewSettings footing (the design-system Slider — an accent-over-track fill with the shared glass knob), drafting live while dragging and writing the view on release; the scrub is scoped per view so a sibling cards embed on the same surface isn't dragged along. The scale factor persists as `card_size` (a number; legacy small/medium/large names map to a factor on read, and a non-finite value is rejected to the default).

#### II. Card Image

A per-view **Card Banner** control chooses the image source: **Cover** (the page's `cover` banner), **Preview** (the captured page thumbnail, the nav gallery's pipeline), or **None** (imageless, compact cards — the band rhythm tightens with them). A page lacking an image under Cover/Preview shows the placeholder, so heights stay uniform within a view. Right-clicking the image band pops the native banner menu — Add when the page has no cover, Change / Remove when it does — worded for the view's source (Cover mode says Cover; Preview says Banner) and editing the page's one banner image through the PageHeader flow, so the card refreshes live on the write. The Preview thumbnail rides the one shared, persistent thumbnail cache.

#### II. Layouts

Card layout is the view's `format`, per-renderer in meaning (Table: density; Cards: layout):

- **Standard** — the title, then one labeled row per visible property: label left, value right.
- **Compact** — the title, then label-less values flowing in property order, tightly packed, never wrapping.

Imageless (Banner: None) cards reserve a bottom area of the title plus two property-value rows — the first two properties fill the reserve before the card grows — so they read as cards rather than flat rows; the location footing, when shown, adds its own height below the reserve. Two LayoutPane switches shape them further: **Wrap Titles** (on lets the title wrap; off keeps it single-line via the shared overflow-scroll) and **Hide Icons**. A value never wraps in either layout — chips keep their hover-scroll mechanics, text-shaped values clamp.

#### II. Properties on Cards

Cards show every visible property (the view's `property_order` minus `hidden_properties`), rendered through the shared chip/cell renderers. Each value is interactive on the ratified per-kind gesture matrix (the same surface the table cells use): a click opens the value's picker — status/select/multi/context/tier open the dropdown, a checkbox toggles, a date opens the calendar, a url opens the LINK dropdown (the URL editable in place, alias riding along; the rendered anchor itself still opens the link), and a number opens the inline editor. A right-click opens the value's native menu off the shared cell-menu model — the per-kind items (Clear · Style · Edit) plus a trailing **Remove** that drops the property from the view (its order slot is remembered, and an empty cell that would otherwise have no menu still gets the bare Remove). Because the whole card is a drag handle, each interactive value stops the drag's pointer capture so its click survives; the card still drags from its thumb and title.

The portal pickers — the value picker, its calendar, and the add menu — mount at **one grid-level host** rather than inside the cards, so row churn (a commit that regroups, a re-sort, a band collapse) can never tear an open picker out: values resolve live off the current row, a dead anchor freezes in place, and a value Compact drops mid-edit dismisses animated. Every picker Blooms in AND out (PickerMenu enforces it — a dev warning fires if one is ever unmounted mid-open). A chip's remove-× is inert until its hover reveal: an un-hovered click falls through and opens the picker, so a short chip can never lose a value to a stray click; below the embed-zoom floor the multi-select × drops entirely.

Adding a value comes from the **two-stage add-picker** (G-1), whose list is everything NOT currently shown on the card: hidden properties and tiers, plus any revealed-but-blank property (Compact drops blanks, so they stay addable to re-fill). A blank pane-bearing kind slides into its value pane — chip kinds author their options, a number its editor, tiers/contexts the context picker — while the DEPENDENT dropdown kinds (date, url) exit the add menu entirely and open their own picker at the same anchor, revealing the property on the first committed value (a dismissed, untouched picker reveals nothing). A checkbox — and any hidden-but-filled property — reveals on pick instead (the box on the card is the toggle). Pane-bearing entries group to the top, reveal-only entries below, property order preserved within each group. The add-picker opens from a Compact card's empty flow space, from a card's location footing, or from the native card menu's **Add Property ▸** submenu (the add path when a card has no in-body surface).

#### II. Grouping, Location & Sorting

Cards never indent: structural (location) grouping renders a flat disclosure band per top-level Set, its whole subtree's pages rolled up under it; sub-set nesting never indents a card. A property group replaces the location bands with bucket bands. Ungrouped/root pages band under the container's own heading rather than a header-less tail. Band chrome is collapse (persisted) plus a hover **"+"** on structural bands only (inert until the creation-affordance design lands). No sub-grouping and no heading columns apply.

**Flattening** is **Group By: None** — the `flat` grouping, rendered as one fully headerless list (no bands, force-open). **Sort By: Location** is a Sort By entry (a peer of Title / Modified / the sortable properties, not a rankable criterion — the sorter has no set tree, so it's ordered at the resolve level). Its Order picker is **Location / Custom** — the table's Group-By-Location order reused (`structural_order_mode`), never Ascending/Descending: Location = filesystem order (drag off, computed), Custom = the view's manual order (drag on). The flat, filesystem-ordered list is **Group By: None + Sort By: Location (Order: Location)**, and it shows each card's full location footing.

Each card's **location footing** is a Set / sub-Set breadcrumb governed by a standing **Hide Location** switch, independent of grouping mode. Under structural grouping the band header already names the top-level Set, so the footing drops that leading crumb; in a flat (Group By: None) or property list — no location band header — it shows the full chain.

#### II. Set Cards

A **Set Cards** switch adds a leading row of larger cards, one per Set (or per depth-1 sub-Set in a Set view) — banner (placeholder when unset) + icon + title. Clicking a Set Card navigates to the Set; the Cards row is reorderable by drag (writing the container's set order). A container with no Sets shows no row; an empty Set still gets its card.

#### II. Card Drag & Menus

Cards reorder within their band by displacement (the nav gallery's drag), writing the per-machine manual order the pipeline reads as its lowest-priority sort tiebreaker; two effective sort criteria retire the drag, and Sort By: Location on its filesystem Order disables it (the order is computed). Cross-band drops are a follow-up.

A card's **right-click** opens a native menu: Open · Rename · Change Icon · Delete, plus the Add Property ▸ submenu — Rename mounts the shared text picker, Change Icon the icon picker. A value's own right-click menu takes precedence over the card menu.

#### II. Surfaces & Insets

Cards live in the ViewSettings type grid (activated alongside Table) and carry their options in the Layout leaf: the Card Banner picker, the Hide Location / Wrap Titles / Hide Icons / Set Cards switches, with Style (the two-option flip toggle) and Scale pinned in the footing. The grouping and sorting leaves reuse the shared panes. A view switched to a type inherits the new type's default glyph only when it still wore the old default. Cards ride the block-surface inset regime: in a full-page pane a pane-body rule supplies the surface inset so the view itself never pads, while an embedded cards view (a view tile on a block surface) runs the tight inter-tile lane directly on its grid — the whole-page surface inset composes that same lane onto a floating-sidebar clearance a tile has already gotten, so a tile needs only the bare lane rather than sitting flush to the edge.

### Pending

- **Compact styling** — the Compact layout's flow packing and imageless-card rhythm are a build-then-sign-off pass.
- **Heading "+" creation** — the structural-band "+" is visual only until the page-creation affordance is designed.

### Prospects

- **Set-Card view previews** — a Set Card opening a preview of the Set's view (needs preview-views); v1 navigates.
- **File-property covers** — any File property declaring itself the card's image (needs a nexus-root read scope + an attach picker); the Card Banner mode set is extensible for a fourth "Property" mode.
- **Fit Image / Reposition** — contain-vs-fill and hover-reposition on covers; v1 is fill-crop.
- **Cross-group card drag** — a card dropped into another location or property band as a real move / property write.
- **Fuller band chrome** — band drag, a native band-header menu, and inline band rename (table territory today).
