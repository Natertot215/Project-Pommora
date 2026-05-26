import SwiftUI

/// Picker for the `DateFormat` "Display as" config on Date / Date & Time
/// properties. Six cases: monthDayLong / monthDayYearLong / numericShort /
/// numericMedium / numericLong / iso. Bound value is optional — nil reads
/// as the `.monthDayYearLong` default at the call site.
///
/// Used by EditPropertyPane's Display as row for Date + DateTime types.
struct DateFormatPicker: View {
    @Binding var format: DateFormat?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Display as")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Display as", selection: $format) {
                Text("Default").tag(DateFormat?.none)
                ForEach(DateFormat.allCases, id: \.self) { fmt in
                    Text(label(for: fmt)).tag(DateFormat?.some(fmt))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func label(for fmt: DateFormat) -> String {
        switch fmt {
        case .monthDayLong: return "March 4"
        case .monthDayYearLong: return "March 4, 2026"
        case .numericShort: return "03-04"
        case .numericMedium: return "03-04-26"
        case .numericLong: return "03-04-2026"
        case .iso: return "2026-03-04"
        }
    }
}

extension DateFormat: CaseIterable {
    public static var allCases: [DateFormat] {
        [.monthDayLong, .monthDayYearLong, .numericShort, .numericMedium, .numericLong, .iso]
    }
}
