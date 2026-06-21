import SwiftUI

/// Component-scoped design tokens for the `DateTimePicker` — the calendar
/// grid's sizes/opacities and the typography that the shared `PUI` scale
/// doesn't carry. Per `Design.md` ("extend rather than inline a literal"),
/// every raw value the picker uses lives here; semantic `Font` styles are used
/// wherever they fit.
enum DateTimePickerMetrics {
    // Grid geometry (condensed)
    /// Day-cell square (also the weekday-header column width).
    static let cell: CGFloat = 34
    /// Weekday-symbol header row height.
    static let weekdayRowHeight: CGFloat = 18
    /// Spacing between the weekday header and the grid, and between grid rows.
    static let gridRowSpacing: CGFloat = 2
    /// Fixed height of the calendar region (≈ a 6-week grid) — reserved so
    /// month-length variance (4 / 5 / 6 weeks) never changes the card's overall
    /// size. The grid sits top-aligned (a short month shows one blank trailing
    /// week); the month-jump menu fills the same region. "Just enough" to fit
    /// the worst case, nothing more.
    static var calendarHeight: CGFloat {
        weekdayRowHeight + gridRowSpacing + 6 * (cell + gridRowSpacing)
    }

    // Card
    static let cardPadding: CGFloat = PUI.Spacing.md

    // Selection fills (opacity over the accent color)
    static let selectedFillOpacity: Double = 0.9
    static let betweenFillOpacity: Double = 0.15
    static let todayRingOpacity: Double = 0.55

    // Header month-step segmented control
    static let stepSegmentWidth: CGFloat = 22
    static let stepSegmentHeight: CGFloat = 20
    static let stepSegmentDividerHeight: CGFloat = 13

    // Time row
    static let timeFieldWidth: CGFloat = 24
    static let stepperWidth: CGFloat = 14
    static let stepperHeight: CGFloat = 11

    // Month menu (year-grouped) — years shown around the viewed year.
    static let yearsBack = 3
    static let yearsForward = 3
    // Month-jump popover dimensions — floats above the picker card.
    static let monthMenuWidth: CGFloat = cell * 7
    static let monthMenuHeight: CGFloat = 220

    // Typography — semantic styles where they fit; explicit only for the small
    // glyphs the scale doesn't reach.
    static let titleFont: Font = .title3.weight(.semibold)         // "June 2026", emphasized
    static let stepGlyphFont: Font = .callout.weight(.bold)        // emphasized ‹ ›
    static let dayFont: Font = .callout
    static let weekdayFont: Font = .caption
    static let timeDigitFont: Font = .callout.monospacedDigit()
    static let amPmFont: Font = .caption.weight(.semibold)
    static let stepperGlyphFont: Font = .system(size: 7, weight: .bold)
    static let menuChevronFont: Font = .system(size: 10, weight: .semibold)
}
