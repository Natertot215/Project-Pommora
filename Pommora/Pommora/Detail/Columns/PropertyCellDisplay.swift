import SwiftUI

/// Per-type read-side cell renderer for property values inside the four
/// storage detail-view Tables (Phase G — Tasks 17/18).
///
/// Render shape per type (locked decisions):
/// - Chip-family (4 types):
///     - Select / MultiSelect → `PropertyChip(.pill)` in option color
///     - Status → switches on `definition.displayAs` (default `.select`
///       colored chip / `.box` colored dot / `.chip` icon-only). nil resolves
///       to `.select` to match the editor binding (which stores nil for it).
///     - Relation → `RelationChip` (default-grey, rounded rectangle,
///       resolved-target icon + title)
/// - Non-chip (7 types):
///     - Number → Text(NumberFormatter per `numberFormat`)
///     - Checkbox → Image(systemName:)
///     - Date / DateTime → Text(DateFormatter per `dateFormat`)
///     - URL → `LinkChip` (accent-blue text, strips https://, 15-char trunc)
///     - File → multiple `FileChip` in a FlowLayout
///     - LastEditedTime → relative-date Text
///
/// Empty values render as a blank cell (full-area clickable wrapping lands
/// in Task 19's PropertyCellEditor).
///
/// Relation target resolution: the cell receives a `RelationResolver`
/// closure from the call site (Tasks 17/18) so this view stays pure of
/// IndexQuery / manager dependencies. The resolver returns (icon, title)
/// for a ULID or `nil` if the target is missing.
struct PropertyCellDisplay: View {
    let definition: PropertyDefinition
    let value: PropertyValue?
    let relationResolver: (String) -> (icon: String, title: String)?

    init(
        definition: PropertyDefinition,
        value: PropertyValue?,
        relationResolver: @escaping (String) -> (icon: String, title: String)? = { _ in nil }
    ) {
        self.definition = definition
        self.value = value
        self.relationResolver = relationResolver
    }

    var body: some View {
        Group {
            switch definition.type {
            case .number:
                numberCell
            case .checkbox:
                checkboxCell
            case .date:
                dateCell
            case .datetime:
                datetimeCell
            case .select:
                selectCell
            case .multiSelect:
                multiSelectCell
            case .status:
                statusCell
            case .url:
                urlCell
            case .relation:
                relationCell
            case .file:
                fileCell
            case .lastEditedTime:
                lastEditedCell
            }
        }
    }

    // MARK: - Empty helper

    @ViewBuilder
    private var emptyCell: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
    }

    // MARK: - Number

    @ViewBuilder
    private var numberCell: some View {
        if case .number(let n) = value {
            Text(formattedNumber(n))
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
        } else { emptyCell }
    }

    private func formattedNumber(_ n: Double) -> String {
        let f = NumberFormatter()
        switch definition.numberFormat ?? .decimal {
        case .integer:
            f.maximumFractionDigits = 0
            return f.string(from: NSNumber(value: n)) ?? "\(Int(n))"
        case .decimal:
            f.numberStyle = .decimal
            return f.string(from: NSNumber(value: n)) ?? "\(n)"
        case .percent:
            f.numberStyle = .percent
            return f.string(from: NSNumber(value: n)) ?? "\(n)%"
        case .currency:
            f.numberStyle = .currency
            return f.string(from: NSNumber(value: n)) ?? "\(n)"
        }
    }

    // MARK: - Checkbox

    @ViewBuilder
    private var checkboxCell: some View {
        let checked: Bool = {
            if case .checkbox(let b) = value { return b }
            return false
        }()
        Image(systemName: checked ? "checkmark.square.fill" : "square")
            .font(.system(size: 13))
            .foregroundStyle(checked ? Color.accentColor : .secondary)
    }

    // MARK: - Date / DateTime

    @ViewBuilder
    private var dateCell: some View {
        if case .date(let d) = value {
            Text(formattedDate(d, includesTime: false))
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
        } else { emptyCell }
    }

    @ViewBuilder
    private var datetimeCell: some View {
        if case .datetime(let d) = value {
            Text(formattedDate(d, includesTime: true))
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
        } else { emptyCell }
    }

    private func formattedDate(_ date: Date, includesTime: Bool) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone.current
        switch definition.dateFormat ?? .monthDayYearLong {
        case .monthDayLong:
            f.dateFormat = "MMMM d"
        case .monthDayYearLong:
            f.dateFormat = "MMMM d, yyyy"
        case .numericShort:
            f.dateFormat = "MM-dd"
        case .numericMedium:
            f.dateFormat = "MM-dd-yy"
        case .numericLong:
            f.dateFormat = "MM-dd-yyyy"
        case .iso:
            f.dateFormat = includesTime ? "yyyy-MM-dd'T'HH:mm:ssZ" : "yyyy-MM-dd"
        }
        var base = f.string(from: date)
        if includesTime, definition.dateFormat != .iso {
            let t = DateFormatter()
            t.timeStyle = .short
            base += " \(t.string(from: date))"
        }
        return base
    }

    // MARK: - Select / MultiSelect

    @ViewBuilder
    private var selectCell: some View {
        if case .select(let optionValue) = value,
           let opt = definition.selectOptions?.first(where: { $0.value == optionValue })
        {
            PropertyChip(label: opt.label, color: chipColor(from: opt.color), size: .compact)
        } else { emptyCell }
    }

    @ViewBuilder
    private var multiSelectCell: some View {
        if case .multiSelect(let ids) = value, !ids.isEmpty {
            HStack(spacing: 4) {
                ForEach(ids, id: \.self) { id in
                    if let opt = definition.selectOptions?.first(where: { $0.value == id }) {
                        PropertyChip(label: opt.label, color: chipColor(from: opt.color), size: .compact)
                    }
                }
            }
        } else { emptyCell }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusCell: some View {
        // nil resolves to `.select` to match the editor's binding (which writes
        // nil for "Select") — otherwise the pill variant would be unreachable.
        let variant = definition.displayAs ?? .select
        if variant == .box {
            // Box always renders the standard tri-state checkbox (empty when
            // unset); the group→state mapping lives in StatusCheckbox.
            StatusCheckbox(value: statusValue, groups: definition.statusGroups ?? [])
        } else if let optionValue = statusValue,
                  let (option, group) = findStatusOption(value: optionValue) {
            let color = chipColor(from: option.color ?? group.color)
            if variant == .chip {
                PropertyChip(icon: "square.dashed", color: color, size: .compact)
            } else {
                PropertyChip(label: option.label, color: color, size: .compact)
            }
        } else {
            emptyCell
        }
    }

    private var statusValue: String? {
        if case .status(let v) = value { return v }
        return nil
    }

    private func findStatusOption(value: String) -> (
        PropertyDefinition.StatusOption, PropertyDefinition.StatusGroup
    )? {
        guard let groups = definition.statusGroups else { return nil }
        for g in groups {
            if let opt = g.options.first(where: { $0.value == value }) {
                return (opt, g)
            }
        }
        return nil
    }

    // MARK: - URL

    @ViewBuilder
    private var urlCell: some View {
        if case .url(let u) = value {
            LinkChip(url: u)
        } else { emptyCell }
    }

    // MARK: - Relation

    @ViewBuilder
    private var relationCell: some View {
        if case .relation(let targetIDs) = value, !targetIDs.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(targetIDs.prefix(3).enumerated()), id: \.offset) { _, targetID in
                    if let resolved = relationResolver(targetID) {
                        RelationChip(icon: resolved.icon, title: resolved.title)
                    } else {
                        Text("(missing)")
                            .font(.system(size: 12).italic())
                            .foregroundStyle(.tertiary)
                    }
                }
                if targetIDs.count > 3 {
                    Text("+\(targetIDs.count - 3)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        } else { emptyCell }
    }

    // MARK: - File

    @ViewBuilder
    private var fileCell: some View {
        if case .file(let refs) = value, !refs.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(refs.prefix(3).enumerated()), id: \.offset) { _, ref in
                    FileChip(filename: ref.originalName)
                }
                if refs.count > 3 {
                    Text("+\(refs.count - 3)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        } else { emptyCell }
    }

    // MARK: - LastEditedTime

    @ViewBuilder
    private var lastEditedCell: some View {
        // The cell receives the resolved Date via the value parameter as a
        // `.datetime` (call sites adapt the file's modified_at into a
        // PropertyValue.datetime so the dispatcher renders uniformly).
        if case .datetime(let d) = value {
            Text(relativeText(d))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if case .date(let d) = value {
            Text(relativeText(d))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else { emptyCell }
    }

    private func relativeText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Color bridge

    /// Map persistence-layer SelectColor (or nil) to the UI PropertyChipColor
    /// — same bridge as EditOptionPane. `.gray` (SelectColor) → `.default`.
    private func chipColor(from select: PropertyDefinition.SelectColor?) -> PropertyChipColor {
        guard let select else { return .default }
        switch select {
        case .gray: return .default
        case .brown: return .brown
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        }
    }
}
