import SwiftUI

/// The month-jump list opened by the header chevron. Grouped **by year** — a
/// year heading followed by its month names — windowed around the currently-
/// viewed year so past dates (birthdays, created-on, historical records) are
/// reachable. The viewed month is marked and scrolled into view; each re-open
/// re-centers on wherever the calendar now sits.
///
/// Rendered as plain content (no own panel) — it's swapped in over the grid
/// inside the picker's single glass card, so it must not draw a second surface.
struct MonthYearMenu: View {
    /// The month the calendar is currently showing (highlighted + centered).
    let visibleMonth: CalendarMonth
    let onSelect: (CalendarMonth) -> Void

    private let calendar: Calendar = .current

    private struct YearGroup: Identifiable {
        let year: Int
        let months: [CalendarMonth]
        var id: Int { year }
    }

    /// `visibleYear ± window`, each year carrying its twelve months.
    private var yearGroups: [YearGroup] {
        let visibleYear = calendar.component(.year, from: visibleMonth.monthStart)
        let years = (visibleYear - DateTimePickerMetrics.yearsBack)...(visibleYear + DateTimePickerMetrics.yearsForward)
        return years.map { year in
            let months = (1...12).compactMap { month -> CalendarMonth? in
                guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1))
                else { return nil }
                return CalendarMonth(containing: date, calendar: calendar)
            }
            return YearGroup(year: year, months: months)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: PUI.Spacing.xs) {
                    ForEach(yearGroups) { group in
                        Text(verbatim: "\(group.year)")
                            .font(PUI.Typography.sectionHeader)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, PUI.Spacing.md)
                            .padding(.top, PUI.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(group.months, id: \.monthStart) { month in
                            MonthRow(
                                name: month.monthName,
                                isCurrent: calendar.isDate(
                                    month.monthStart,
                                    equalTo: visibleMonth.monthStart,
                                    toGranularity: .month
                                ),
                                onTap: { onSelect(month) }
                            )
                            .id(month.monthStart)
                        }
                    }
                }
                .padding(PUI.Spacing.sm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                proxy.scrollTo(visibleMonth.monthStart, anchor: .center)
            }
        }
    }
}

/// One month row (name only — the year is the section heading). Hover fill + a
/// check on the currently-viewed month.
private struct MonthRow: View {
    let name: String
    let isCurrent: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: PUI.Spacing.sm) {
                Text(name)
                    .font(PUI.Typography.row)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, PUI.Spacing.md)
            .padding(.vertical, PUI.Spacing.xs)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: PUI.Radius.card, style: .continuous)
                    .fill(rowFill)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var rowFill: Color {
        if isCurrent { return Color.primary.opacity(0.10) }
        return PUI.Fill.hover(isHovered)
    }
}
