import SwiftUI

/// The date picker's bottom time row — a bespoke `HH : MM` entry with ▲▼
/// steppers, plus an AM/PM toggle in 12-hour mode. Deliberately *not* the
/// native stepper-field or a wheel: it's a Component-Library control styled to
/// the glass card with the house `.fieldBackground()` pill, keyboard-first and
/// mouse-steppable. Edits the time portion of `date`, preserving its day.
struct TimeFieldRow: View {
    @Binding var date: Date
    let is24Hour: Bool

    private let calendar: Calendar = .current

    var body: some View {
        HStack(spacing: PUI.Spacing.md) {
            Text("Time")
                .font(PUI.Typography.row)
                .foregroundStyle(.secondary)
            Spacer(minLength: PUI.Spacing.md)
            HStack(spacing: PUI.Spacing.sm) {
                SteppableNumberField(value: hourBinding, range: hourRange)
                Text(":")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                SteppableNumberField(value: minuteBinding, range: 0...59, zeroPadded: true)
                if !is24Hour {
                    AMPMToggle(isPM: isPMBinding)
                }
            }
        }
    }

    // MARK: - Time arithmetic

    private var hourRange: ClosedRange<Int> { is24Hour ? 0...23 : 1...12 }

    private var hourBinding: Binding<Int> {
        Binding(
            get: {
                let h = calendar.component(.hour, from: date)
                return is24Hour ? h : DateTimeMath.hour12(fromHour24: h).hour
            },
            set: { newHour in
                let hour24: Int
                if is24Hour {
                    hour24 = newHour
                } else {
                    let isPM = calendar.component(.hour, from: date) >= 12
                    hour24 = DateTimeMath.hour24(fromHour12: newHour, isPM: isPM)
                }
                date = DateTimeMath.setting(
                    hour: hour24, minute: calendar.component(.minute, from: date), on: date
                )
            }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.minute, from: date) },
            set: { date = DateTimeMath.setting(hour: calendar.component(.hour, from: date), minute: $0, on: date) }
        )
    }

    private var isPMBinding: Binding<Bool> {
        Binding(
            get: { calendar.component(.hour, from: date) >= 12 },
            set: { pm in
                let h = calendar.component(.hour, from: date)
                guard pm != (h >= 12) else { return }
                let newHour = pm ? h + 12 : h - 12
                date = DateTimeMath.setting(hour: newHour, minute: calendar.component(.minute, from: date), on: date)
            }
        )
    }
}

// MARK: - Number field with steppers

/// A small typeable integer field clamped to `range`, with ▲▼ wrap-around
/// steppers. Typing updates live (digits clamped); the steppers wrap at bounds.
private struct SteppableNumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var zeroPadded: Bool = false

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 2) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(DateTimePickerMetrics.timeDigitFont)
                .frame(width: DateTimePickerMetrics.timeFieldWidth)
                .focused($focused)
                .padding(.horizontal, PUI.Spacing.sm)
                .padding(.vertical, PUI.Spacing.xs)
                .fieldBackground()
                .onChange(of: text) { _, newText in commit(newText) }
                .onChange(of: value) { _, newValue in if !focused { text = format(newValue) } }
                .onChange(of: focused) { _, isFocused in if !isFocused { text = format(value) } }
                .onAppear { text = format(value) }

            VStack(spacing: 0) {
                stepButton(icon: "chevron.up", delta: 1)
                stepButton(icon: "chevron.down", delta: -1)
            }
        }
    }

    private func stepButton(icon: String, delta: Int) -> some View {
        Button {
            var next = value + delta
            if next > range.upperBound { next = range.lowerBound }
            if next < range.lowerBound { next = range.upperBound }
            value = next
            text = format(next)
        } label: {
            Image(systemName: icon)
                .font(DateTimePickerMetrics.stepperGlyphFont)
                .foregroundStyle(.secondary)
                .frame(width: DateTimePickerMetrics.stepperWidth, height: DateTimePickerMetrics.stepperHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func commit(_ raw: String) {
        let digits = raw.filter(\.isNumber)
        guard let parsed = Int(digits) else { return }
        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
        if clamped != value { value = clamped }
    }

    private func format(_ v: Int) -> String {
        zeroPadded ? String(format: "%02d", v) : "\(v)"
    }
}

// MARK: - AM/PM toggle

/// Two-segment AM/PM control. Active segment fills with the per-Nexus accent.
private struct AMPMToggle: View {
    @Binding var isPM: Bool
    @Environment(\.nexusAccent) private var accent

    var body: some View {
        HStack(spacing: 0) {
            segment("AM", active: !isPM) { isPM = false }
            segment("PM", active: isPM) { isPM = true }
        }
        .fieldBackground()
    }

    private func segment(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DateTimePickerMetrics.amPmFont)
                .foregroundStyle(active ? accent.contrastingForeground : Color.secondary)
                .padding(.horizontal, PUI.Spacing.md)
                .padding(.vertical, PUI.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: PUI.Radius.field, style: .continuous)
                        .fill(accent.opacity(active ? DateTimePickerMetrics.selectedFillOpacity : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
