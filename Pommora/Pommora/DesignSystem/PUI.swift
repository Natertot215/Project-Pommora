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
        /// 2 pt — hairline gaps (chip internals, tight icon-label stacks).
        static let xxs: CGFloat = 2
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
        /// Banner band height — shared by the container banner and the homepage
        /// banner so both adopt one source of truth.
        static let bannerHeight: CGFloat = 180
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

        /// Fixed point sizes for density-driven surfaces that deliberately opt
        /// out of Dynamic Type (table / gallery cells, chips, compact rows).
        /// Prefer a semantic token above — or a `PUI.Icon` role for glyphs —
        /// when one fits; reach here only for a genuinely fixed text size with
        /// no semantic home.
        enum Fixed {
            static let f10: Font = .system(size: 10)
            static let f11: Font = .system(size: 11)
            static let f12: Font = .system(size: 12)
            static let f13: Font = .system(size: 13)
            static let f14: Font = .system(size: 14)
            static let f18: Font = .system(size: 18)
            static let f22: Font = .system(size: 22)
            static let f26: Font = .system(size: 26)
            static let f28: Font = .system(size: 28)
            static let f36: Font = .system(size: 36)
            static let f48: Font = .system(size: 48)
        }
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
        /// Input / icon-field backdrop (system `.quinary`). Apply via `.fieldBackground()`.
        static let field = AnyShapeStyle(.quinary)
        /// Hover-state background opacity — the faint fill under a hovered
        /// row / cell / segment. Single source for the `.opacity(isHovered ? … : 0)`
        /// hover idiom across pickers, rows, and segments.
        static let hoverOpacity: Double = 0.06
        /// The hover fill resolved to a color: `base` at `hoverOpacity` when
        /// hovered, fully clear otherwise. Drop-in for the
        /// `base.opacity(isHovered ? … : 0)` idiom — including branches where
        /// hover shares the fill with other state.
        static func hover(_ isHovered: Bool, over base: Color = .primary) -> Color {
            base.opacity(isHovered ? hoverOpacity : 0)
        }
    }

    // MARK: - Chip geometry (tag insets + gaps)

    /// Insets + gaps the chip bodies and `.chipStyle` reference instead of
    /// inline literals. Radii route through `Radius`.
    enum Chip {
        static let tagPaddingHorizontal: CGFloat = Spacing.md
        static let tagPaddingVertical: CGFloat = Spacing.xs
        static let filePaddingHorizontal: CGFloat = Spacing.sm
        static let filePaddingVertical: CGFloat = 3
        static let iconTitleGap: CGFloat = 5
        static let fileIconTitleGap: CGFloat = Spacing.xs
        /// Faint tags: the stroke out-opaques its fill, so 0.5pt reads.
        static let strokeWidth: CGFloat = 0.5
        /// Strong chips: the border is the full chip color, so it needs more weight.
        static let borderWidth: CGFloat = 1
    }

    // MARK: - Colors (css-like, nexus-wide semantic palette)

    /// The named palette the chip tints route to — a `:root` of color tokens, so
    /// a palette change is one edit.
    enum Colors {
        static let labelPrimary = Color.primary
        static let labelSecondary = Color.secondary
        /// Neutral base the relation / file tag tints derive from.
        static let chipBase = Color.primary
        static let accent = Color.accentColor
    }

    // MARK: - Tints (opacity ramp over a base color)

    /// A *tint* is a base color at one of four fixed opacities — chips share this
    /// single ramp instead of hand-rolled `.opacity(…)` multipliers.
    enum Tint {
        static func primary(_ base: Color) -> Color { base.opacity(0.70) }
        static func secondary(_ base: Color) -> Color { base.opacity(0.50) }
        static func tertiary(_ base: Color) -> Color { base.opacity(0.25) }
        static func quaternary(_ base: Color) -> Color { base.opacity(0.125) }

        /// `labelPrimary` nudged toward the base — the readable "label with the
        /// tint overlaid," not the base at 12.5%.
        static func label(_ base: Color) -> Color {
            Colors.labelPrimary.mix(with: base, by: 0.125)
        }
    }

    // MARK: - Typography (chip labels)

    /// Tag label font — lighter (medium) than the saturated pill's `Typography.chip`.
    enum ChipLabel {
        static let tag: Font = .system(size: 12, weight: .medium)
    }
}
