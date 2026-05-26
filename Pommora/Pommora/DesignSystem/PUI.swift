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
        /// Standard popover frame height.
        static let height: CGFloat = 360
        /// Inner content padding (for scrollable pane bodies).
        static let contentPadding: CGFloat = Spacing.xxl

        /// Inline header zone (PaneHeader): back chevron + title row.
        enum Header {
            static let paddingHorizontal: CGFloat = Spacing.xl
            static let paddingTop: CGFloat = 14
            static let paddingBottom: CGFloat = Spacing.md
            static let chevronFrame: CGFloat = 22
            static let interSpacing: CGFloat = Spacing.md
        }
    }

    // MARK: - Icons (Font + frame per role)

    enum Icon {
        /// Row leading icon (the row's symbol — folder/eye/lock/file-stack).
        static let leading: Font = .system(size: 13, weight: .regular)
        /// Row leading icon frame width — keeps labels left-aligned across rows.
        static let leadingFrame: CGFloat = 18

        /// Inline header icon (StorageMenuRoot type icon, EditPropertyPane title icon).
        static let header: Font = .system(size: 14, weight: .medium)
        /// Inline header icon frame.
        static let headerFrame: CGFloat = 22

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
    }

    // MARK: - Typography

    enum Typography {
        /// Pane header title.
        static let paneTitle: Font = .headline
        /// Default row label.
        static let row: Font = .callout
        /// Row subtitle (type label under a property name, etc.).
        static let rowSubtitle: Font = .caption2
        /// Section header label (above a group of rows).
        static let sectionHeader: Font = .caption
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
        /// 12 pt — large controls.
        static let large: CGFloat = 12
        /// 18 pt — inset list trough (NavDropdown).
        static let listTrough: CGFloat = 18
        /// 24 pt — outer popover container.
        static let popover: CGFloat = 24
    }
}
