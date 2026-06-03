import SwiftUI

/// Pommora's custom Liquid-Glass date (+ time) picker — replaces the stock
/// `.graphical` `DatePicker` in property editors.
///
/// A glass card with three zones:
///   • **Header** — month/year label + a chevron that drops a month menu, plus
///     prev/next step arrows.
///   • **Grid** — a locale-aware calendar; selection is the per-Nexus accent at
///     a translucent fill, range in-between days get an even lighter band, and
///     today carries a hairline accent ring.
///   • **Time row** (optional) — below a divider, shown when `showsTime`.
///
/// Selection is `DateSelection?` (single | range). Property cells bind in
/// `.single` mode; `.range` is reserved for Agenda events and the showcase.
struct DateTimePicker: View {
    @Binding var selection: DateSelection?
    var mode: DateSelection.Mode = .single
    var timeFormat: TimeFormat = .none

    @Environment(\.nexusAccent) private var accent

    private var showsTime: Bool { timeFormat.showsTime }

    @State private var visibleMonth: CalendarMonth
    @State private var monthMenuOpen = false
    @State private var headerHovered = false
    /// First tap of a range, awaiting its second (range mode only).
    @State private var pendingRangeStart: Date?

    init(
        selection: Binding<DateSelection?>,
        mode: DateSelection.Mode = .single,
        timeFormat: TimeFormat = .none
    ) {
        _selection = selection
        self.mode = mode
        self.timeFormat = timeFormat
        let anchor = selection.wrappedValue?.anchorDate ?? Date()
        _visibleMonth = State(initialValue: CalendarMonth(containing: anchor))
    }

    var body: some View {
        VStack(spacing: PUI.Spacing.md) {
            header
            Divider()
            calendarArea
            if showsTime {
                Divider()
                TimeFieldRow(
                    date: selectedDateBinding,
                    is24Hour: timeFormat == .twentyFourHour
                )
            }
        }
        .frame(width: DateTimePickerMetrics.cell * 7)
        .padding(DateTimePickerMetrics.cardPadding)
        // House Liquid-Glass panel surface (`.regularMaterial`) — same as every
        // other inline floating panel; the popover hosts it chromeless via
        // `.presentationBackground(.clear)` so there's a single glass layer.
        .chipDropdownPanel()
    }

    /// The calendar grid, or the month-jump list swapped in. The region is a
    /// fixed height (≈ 6 weeks) so month-length variance never resizes the
    /// card; the grid is top-aligned (a short month shows one blank trailing
    /// week) and the menu fills the same height. Horizontal swipe on the grid
    /// steps the month.
    @ViewBuilder
    private var calendarArea: some View {
        Group {
            if monthMenuOpen {
                MonthYearMenu(visibleMonth: visibleMonth) { picked in
                    visibleMonth = picked
                    withAnimation(.snappy(duration: 0.15)) { monthMenuOpen = false }
                }
                .transition(.opacity)
            } else {
                CalendarGridView(
                    month: visibleMonth,
                    selection: selection,
                    pendingRangeStart: pendingRangeStart,
                    accent: accent,
                    accentForeground: accentForeground,
                    onPick: handlePick
                )
                .gesture(monthSwipe)
                .transition(.opacity)
            }
        }
        .frame(height: DateTimePickerMetrics.calendarHeight, alignment: .top)
    }

    /// Horizontal swipe across the grid → previous / next month.
    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 40, abs(dx) > abs(value.translation.height) else { return }
                withAnimation(.snappy(duration: 0.18)) {
                    visibleMonth = visibleMonth.adding(months: dx < 0 ? 1 : -1)
                }
            }
    }

    /// Legible foreground (black/white) for text drawn on the accent fill —
    /// fixes white-on-light for the yellow / gray accents.
    private var accentForeground: Color { accent.contrastingForeground }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: PUI.Spacing.sm) {
            Button {
                withAnimation(.snappy(duration: 0.18)) { monthMenuOpen.toggle() }
            } label: {
                HStack(spacing: PUI.Spacing.xs) {
                    Text(visibleMonth.title)
                        .font(DateTimePickerMetrics.titleFont)
                        .foregroundStyle(.primary)
                    // Disclosure chevron: `›` when closed, rotating smoothly to
                    // `⌄` when open. Hidden until hover (or while open).
                    Image(systemName: "chevron.right")
                        .font(DateTimePickerMetrics.menuChevronFont)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(monthMenuOpen ? 90 : 0))
                        .opacity(headerHovered || monthMenuOpen ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) { headerHovered = hovering }
            }

            Spacer(minLength: PUI.Spacing.md)

            MonthStepControl { months in
                withAnimation(.snappy(duration: 0.18)) {
                    visibleMonth = visibleMonth.adding(months: months)
                }
            }
        }
    }

    // MARK: - Time

    /// Single-date binding for the time row. Editing the time rewrites the
    /// selection's date in place (the start date, for a range).
    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: { selection?.anchorDate ?? Date() },
            set: { newValue in
                switch selection {
                case .range(_, let end):
                    selection = .range(newValue, end)
                default:
                    selection = .single(newValue)
                }
            }
        )
    }

    // MARK: - Selection

    private func handlePick(_ day: Date) {
        // Follow a tapped leading/trailing day into its month.
        if !visibleMonth.isInMonth(day) {
            visibleMonth = CalendarMonth(containing: day)
        }
        switch mode {
        case .single:
            // Preserve any time the user already set when the day changes.
            selection = .single(DateTimeMath.combine(day: day, time: selection?.anchorDate ?? day))
        case .range:
            if let start = pendingRangeStart {
                let lo = min(start, day), hi = max(start, day)
                selection = .range(lo, hi)
                pendingRangeStart = nil
            } else {
                pendingRangeStart = day
            }
        }
    }
}

// MARK: - Calendar grid

/// Weekday header + day grid. Pure presentation: it renders `month` against
/// `selection` and reports taps via `onPick`.
private struct CalendarGridView: View {
    let month: CalendarMonth
    let selection: DateSelection?
    let pendingRangeStart: Date?
    let accent: Color
    let accentForeground: Color
    let onPick: (Date) -> Void

    private let columns = Array(
        repeating: GridItem(.fixed(DateTimePickerMetrics.cell), spacing: 0),
        count: 7
    )

    var body: some View {
        VStack(spacing: DateTimePickerMetrics.gridRowSpacing) {
            HStack(spacing: 0) {
                ForEach(month.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(DateTimePickerMetrics.weekdayFont)
                        .foregroundStyle(.secondary)
                        .frame(width: DateTimePickerMetrics.cell, height: DateTimePickerMetrics.weekdayRowHeight)
                }
            }
            LazyVGrid(columns: columns, spacing: DateTimePickerMetrics.gridRowSpacing) {
                ForEach(month.days, id: \.self) { day in
                    CalendarDayCell(
                        day: day,
                        isInMonth: month.isInMonth(day),
                        role: role(of: day),
                        accent: accent,
                        accentForeground: accentForeground,
                        onTap: { onPick(day) }
                    )
                }
            }
        }
    }

    /// A pending first range-tap previews as a selected day until the second.
    private func role(of day: Date) -> DateSelection.DayRole {
        if let pending = pendingRangeStart,
            Calendar.current.isDate(day, inSameDayAs: pending) {
            return .selected
        }
        return selection?.role(of: day) ?? .none
    }
}

/// One day button. Rendering is isolated to a struct with plain value inputs
/// (no live query types in the closure) per the GRDB `@ViewBuilder` overload
/// caveat, and to keep `onHover` state per-cell.
private struct CalendarDayCell: View {
    let day: Date
    let isInMonth: Bool
    let role: DateSelection.DayRole
    let accent: Color
    let accentForeground: Color
    let onTap: () -> Void

    @State private var isHovered = false
    private let calendar: Calendar = .current

    var body: some View {
        Button(action: onTap) {
            Text("\(calendar.component(.day, from: day))")
                .font(DateTimePickerMetrics.dayFont)
                .foregroundStyle(foreground)
                .frame(
                    width: DateTimePickerMetrics.cell,
                    height: DateTimePickerMetrics.cell
                )
                .background(background)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var background: some View {
        switch role {
        case .selected, .rangeStart, .rangeEnd:
            Circle().fill(accent.opacity(DateTimePickerMetrics.selectedFillOpacity))
        case .between:
            Rectangle().fill(accent.opacity(DateTimePickerMetrics.betweenFillOpacity))
        case .none:
            if calendar.isDateInToday(day) {
                Circle().strokeBorder(
                    accent.opacity(DateTimePickerMetrics.todayRingOpacity),
                    lineWidth: 1
                )
            } else if isHovered {
                Circle().fill(Color.primary.opacity(DateTimePickerMetrics.hoverFillOpacity))
            } else {
                Color.clear
            }
        }
    }

    private var foreground: Color {
        switch role {
        case .selected, .rangeStart, .rangeEnd: return accentForeground
        case .between: return .primary
        case .none: return isInMonth ? .primary : Color.secondary.opacity(0.5)
        }
    }
}

// MARK: - Month step control

/// The prev/next month stepper as a joined two-segment control (`‹ | ›`) on the
/// house field surface, replacing the two loose chevron buttons. `onStep` gets
/// −1 / +1.
private struct MonthStepControl: View {
    let onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            SegmentButton(icon: "chevron.left") { onStep(-1) }
            Divider().frame(height: DateTimePickerMetrics.stepSegmentDividerHeight)
            SegmentButton(icon: "chevron.right") { onStep(1) }
        }
        // Transparent — no field pill; the divider keeps the segmented read.
    }
}

private struct SegmentButton: View {
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DateTimePickerMetrics.stepGlyphFont)
                .foregroundStyle(.primary)
                .frame(
                    width: DateTimePickerMetrics.stepSegmentWidth,
                    height: DateTimePickerMetrics.stepSegmentHeight
                )
                .background(
                    RoundedRectangle(cornerRadius: PUI.Radius.field, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? DateTimePickerMetrics.hoverFillOpacity : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
