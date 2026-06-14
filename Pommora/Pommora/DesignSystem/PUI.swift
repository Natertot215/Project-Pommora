import SwiftUI

/// Pommora's UI design tokens — single source of truth for spacings, paddings,
/// font hierarchy, icon sizing, corner radii, and standard dimensions across
/// every Pommora-custom surface (sidebar rows, View Settings popover panes,
/// detail-view chrome, sheets, popovers, toolbar capsules).
///
/// **Why a tokens module:** before this, every pane file inlined its own raw
/// CGFloat / Font values (`.padding(.horizontal, 12)` here, `.padding(.horizontal, 16)`
/// next door, font sizes scattered 9 → 14 pt across icons with no scale, etc.).
/// The result was visible inconsistency across surfaces the user navigates
/// between. Routing every dimension through this enum forces convergence + makes
/// a future visual refresh a single-file edit.
///
/// **Conventions:**
/// - Spacing scale: `xs / sm / md / lg / xl / xxl / xxxl` — for HStack/VStack
///   `spacing:` values and one-off gaps. Keep raw-numeric spacing out of view
///   bodies; if a token doesn't fit, add a new scale step here.
/// - `Row.*` — dimensions inside a sidebar / pane / list row.
/// - `Pane.*` — popover-pane chrome (frame size, header zone).
/// - `Icon.*` — Font + frame sizes per icon role.
/// - `Typography.*` — semantic Font choices.
/// - `Radius.*` — corner radii.
///
/// **Forbidden** in new code: magic-number paddings. Use the token; if it
/// doesn't fit, extend this file rather than inlining a raw value.
enum PUI {

    // MARK: - Spacing (HStack / VStack `spacing:`, ad-hoc gaps)

    enum Spacing {
        /// 4 pt — tight intra-row gaps (between two adjacent labels, etc.).
        static let xs: CGFloat = 4
        /// 6 pt — compact spacing inside small groups.
        static let sm: CGFloat = 6
        /// 8 pt — default row vertical spacing.
        static let md: CGFloat = 8
        /// 10 pt — row HStack spacing (icon ↔ label ↔ trailing chevron).
        static let lg: CGFloat = 10
        /// 12 pt — pane horizontal padding; section spacing.
        static let xl: CGFloat = 12
        /// 16 pt — pane row horizontal padding; section gap.
        static let xxl: CGFloat = 16
        /// 24 pt — outer popover / large section gap.
        static let xxxl: CGFloat = 24
    }

    // MARK: - Row (sidebar / pane / list row dimensions)

    enum Row {
        /// Horizontal padding inside a pane row (leading + trailing).
        static let paddingHorizontal: CGFloat = Spacing.xxl
        /// Vertical padding inside a pane row (above + below).
        static let paddingVertical: CGFloat = Spacing.md
        /// HStack spacing between row elements (icon ↔ label ↔ trailing chevron).
        static let interSpacing: CGFloat = Spacing.lg
    }

    // MARK: - Pane / Popover

    enum Pane {
        /// Standard popover frame width (View Settings + sub-panes).
        static let width: CGFloat = 300
        /// Minimum popover height — the floor; short panes sit here (today's look).
        static let minHeight: CGFloat = 360
        /// Hard cap — panes grow to fit content up to here, then scroll the
        /// middle (header + footer stay pinned). Nathan-set 2026-06-02.
        static let maxHeight: CGFloat = 500
        /// Inner content padding (for scrollable pane bodies).
        static let contentPadding: CGFloat = Spacing.xxl
        /// Vertical padding above + below an in-content divider (e.g. the
        /// icon/title field ↔ the section list). Dividers span the full
        /// content rail; this is the breathing room around them.
        static let dividerPaddingVertical: CGFloat = 5

        /// Inline header zone (PaneHeader): back chevron + title row.
        enum Header {
            static let paddingHorizontal: CGFloat = Spacing.xl
            static let paddingTop: CGFloat = 14
            static let paddingBottom: CGFloat = Spacing.md
            static let chevronFrame: CGFloat = 22
            static let interSpacing: CGFloat = Spacing.md
        }
    }

    // MARK: - Detail header (storage-view title + icon region)

    enum DetailHeader {
        /// Title + icon font for the storage detail header (Vault / Collection).
        /// `.title` ≈ 22 pt on macOS; bumped from `.title2` (17 pt) 2026-06-13 per
        /// Nathan's "increase the title-bar size across all views".
        static let titleFont: Font = .title.bold()
        /// Header horizontal padding (and the title's inset from the banner's
        /// leading edge when overlaid).
        static let paddingHorizontal: CGFloat = Spacing.xxl
        /// Header vertical padding in the no-banner (plain chrome) layout.
        static let paddingVertical: CGFloat = Spacing.xxl
        /// Title inset up from the banner's bottom edge when overlaid.
        static let overlayInset: CGFloat = Spacing.xxl
    }

    // MARK: - Icons (Font + frame per role)

    enum Icon {
        /// Row leading icon (the row's symbol — folder/eye/lock/file-stack).
        static let leading: Font = .system(size: 13, weight: .regular)
        /// Row leading icon frame width — keeps labels left-aligned across rows.
        static let leadingFrame: CGFloat = 18

        /// Inline header icon (StorageMenuRoot type icon, EditPropertyPane title icon).
        /// Bumped to `.title3` (≈20pt) 2026-05-26 to match the popover-side
        /// title TextField scale per Nathan's direction.
        static let header: Font = .title3
        /// Inline header icon frame.
        static let headerFrame: CGFloat = 28

        /// Trailing chevron — "tap to push" affordance.
        static let chevron: Font = .system(size: 11, weight: .semibold)

        /// Back chevron — "tap to pop" affordance (PaneHeader).
        static let backChevron: Font = .system(size: 12, weight: .semibold)

        /// Add affordance (`+` in section headers, "New property" footer).
        static let plus: Font = .system(size: 12, weight: .semibold)

        /// Lock indicator (reserved / disabled affordances).
        static let lock: Font = .system(size: 9)

        /// Visibility eye / eye-slash on rows.
        static let visibility: Font = .system(size: 11)

        // Toolbar-action glyphs (window-toolbar primary-action + navigation
        // buttons). Height is system-owned by the default toolbar button style;
        // only width is set, via the `.toolbarGlyph(width:)` modifier.

        /// Toolbar-action glyph font — every primary-action / navigation toolbar
        /// button icon (Views, settings, nav, inspector, Back / Forward).
        static let toolbarAction: Font = .system(size: 12, weight: .medium)
        /// Standard toolbar-action hit-target width — the settings · nav ·
        /// inspector trio segments and the Back / Forward buttons.
        static let toolbarActionFrame: CGFloat = 22
        /// Wider Views pill — the single-icon Views button, balanced as its own capsule.
        static let toolbarViewsFrame: CGFloat = 38
    }

    // MARK: - Typography

    enum Typography {
        /// Pane header title.
        static let paneTitle: Font = .headline
        /// Default row label.
        static let row: Font = .callout
        /// Row subtitle (type label under a property name, etc.).
        static let rowSubtitle: Font = .caption2
        /// Section header label (above a group of rows — "Options",
        /// "Display As"). Subheadline / emphasized, rendered vibrant
        /// secondary at the call site. Sized down from `.headline` per
        /// Nathan's 2026-05-27 Figma scale (section-footer feel).
        static let sectionHeader: Font = .subheadline.weight(.semibold)
        /// Option / select chip label — Callout / emphasized (matches the
        /// shipping `PropertyChip` 12pt semibold). Reorder grips + inline
        /// chip-adjacent glyphs size to this.
        static let chip: Font = .callout.weight(.semibold)
        /// Muted / placeholder caption text.
        static let caption: Font = .caption2
    }

    // MARK: - Corner radii

    enum Radius {
        /// 4 pt — small chips, inline badges.
        static let small: CGFloat = 4
        /// 6 pt — inset cards (status group editor box).
        static let card: CGFloat = 6
        /// 8 pt — medium controls.
        static let medium: CGFloat = 8
        /// Input field + icon-button backdrop rounding (rounded-rect, NOT
        /// pill). Native-control feel; verify against the inspector in build.
        static let field: CGFloat = 8
        /// 12 pt — large controls.
        static let large: CGFloat = 12
        /// 18 pt — inset list trough (NavDropdown).
        static let listTrough: CGFloat = 18
        /// 24 pt — outer popover container.
        static let popover: CGFloat = 24
    }

    // MARK: - Fills

    enum Fill {
        /// Input / icon-field backdrop — replaces the old
        /// `Color.primary.opacity(0.06)` capsule "pill" everywhere. Uses the
        /// system `.quinary` hierarchical fill: translucent + appearance-
        /// adaptive, so it sits cleanly on the popover's Liquid Glass backdrop.
        /// (`.controlBackgroundColor` was too stark; `.quaternary` too bright —
        /// 2026-05-27.) Apply via the `.fieldBackground()` modifier.
        static let field = AnyShapeStyle(.quinary)
    }
}
