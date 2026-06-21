import SwiftUI

/// Read-side cell renderer for property values in the detail-view table and
/// gallery.
///
/// Render shape per type:
/// - Chip-family (4 types):
///     - Select / MultiSelect → `PropertyChip(.pill)` in option color
///     - Status → switches on `definition.displayAs` (default `.select`
///       colored chip / `.box` colored dot / `.chip` icon-only). nil resolves
///       to `.select` to match the editor binding (which stores nil for it).
///     - Relation → `ContextChip` (default-grey, rounded rectangle,
///       resolved-target icon + title)
/// - Non-chip (7 types):
///     - Number → Text(NumberFormatter per `numberFormat`)
///     - Checkbox → Image(systemName:)
///     - Date / DateTime → Text(DateFormatter per `dateFormat`)
///     - URL → `LinkChip` (accent-blue text, strips https://, 15-char trunc)
///     - File → multiple `FileChip` in a FlowLayout
///     - LastEditedTime → relative-date Text
///
/// Empty values render as a blank cell.
///
/// Relation target resolution: the cell receives a `RelationResolver` closure
/// from the call site so this view stays pure of IndexQuery / manager
/// dependencies. The resolver returns (icon, title) for a ULID or `nil` if
/// the target is missing.
struct PropertyCellDisplay: View {
    let definition: PropertyDefinition
    let value: PropertyValue?
    /// Per-property render mode (LD-4). Defaults to `.inline` so existing call
    /// sites — Table cells that always want today's chips — compile unchanged.
    /// Only `.file` (`thumbnail`/`banner`) and `.relation` (`list`) diverge.
    let display: PropertyDisplay
    let relationResolver: (String) -> (icon: String, title: String)?

    init(
        definition: PropertyDefinition,
        value: PropertyValue?,
        display: PropertyDisplay = .inline,
        relationResolver: @escaping (String) -> (icon: String, title: String)? = { _ in nil }
    ) {
        self.definition = definition
        self.value = value
        self.display = display
        self.relationResolver = relationResolver
    }

    /// Resolved read-side treatment for this property's (display, type) pair.
    private var treatment: DisplayTreatment { display.treatment(for: definition.type) }

    var body: some View {
        Group {
            switch definition.type {
            case .number:
                numberCell
            case .checkbox:
                checkboxCell
            case .date, .datetime:
                dateCell
            case .select:
                selectCell
            case .multiSelect:
                multiSelectCell
            case .status:
                statusCell
            case .url:
                urlCell
            case .relation:
                contextLinkCell
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
                .font(PUI.Typography.Fixed.f12)
                .foregroundStyle(.primary)
                .lineLimit(1)
        } else {
            emptyCell
        }
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

    /// Unified Date cell. The on-disk value may be `.date` (date-only) or
    /// `.datetime` (with time) — both carry a `Date`; the date/time *display* is
    /// governed by the property's `dateFormat` + `timeFormat`, not the value case.
    @ViewBuilder
    private var dateCell: some View {
        if let d = dateValue {
            Text(formattedDate(d))
                .font(PUI.Typography.Fixed.f12)
                .foregroundStyle(.primary)
                .lineLimit(1)
        } else {
            emptyCell
        }
    }

    private var dateValue: Date? {
        switch value {
        case .date(let d), .datetime(let d): return d
        default: return nil
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let dateStr = (definition.dateFormat ?? .full).string(from: date)
        // Show time only when the stored value is .datetime — a .date value
        // means the user never set a time, even on a datetime property.
        guard case .datetime = value,
            let timeStr = (definition.timeFormat ?? .none).string(from: date)
        else { return dateStr }
        return "\(dateStr) \(timeStr)"
    }

    // MARK: - Select / MultiSelect

    @ViewBuilder
    private var selectCell: some View {
        if case .select(let optionValue) = value,
            let opt = definition.selectOptions?.first(where: { $0.value == optionValue })
        {
            PropertyChip(label: opt.label, color: PropertyChipColor(selectColor: opt.color), size: .compact)
        } else {
            emptyCell
        }
    }

    @ViewBuilder
    private var multiSelectCell: some View {
        if case .multiSelect(let ids) = value, !ids.isEmpty {
            HStack(spacing: PUI.Spacing.xs) {
                ForEach(ids, id: \.self) { id in
                    if let opt = definition.selectOptions?.first(where: { $0.value == id }) {
                        PropertyChip(label: opt.label, color: PropertyChipColor(selectColor: opt.color), size: .compact)
                    }
                }
            }
        } else {
            emptyCell
        }
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
            let (option, group) = definition.statusOption(for: optionValue)
        {
            let color = PropertyChipColor(selectColor: option.color ?? group.color)
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

    // MARK: - URL

    @ViewBuilder
    private var urlCell: some View {
        if case .url(let u) = value {
            LinkChip(url: u)
        } else {
            emptyCell
        }
    }

    // MARK: - Context Link

    @ViewBuilder
    private var contextLinkCell: some View {
        if case .relation(let targetIDs) = value, !targetIDs.isEmpty {
            // `list` display lays the chips out vertically; everything else keeps
            // the inline horizontal run. The chip content is identical either way.
            if treatment == .verticalList {
                VStack(alignment: .leading, spacing: PUI.Spacing.xs) { relationChips(for: targetIDs) }
            } else {
                HStack(spacing: PUI.Spacing.xs) { relationChips(for: targetIDs) }
            }
        } else {
            emptyCell
        }
    }

    @ViewBuilder
    private func relationChips(for targetIDs: [String]) -> some View {
        ForEach(Array(targetIDs.prefix(3).enumerated()), id: \.offset) { _, targetID in
            if let resolved = relationResolver(targetID) {
                ContextChip(icon: resolved.icon, title: resolved.title)
            } else {
                Text("(missing)")
                    .font(PUI.Typography.Fixed.f12.italic())
                    .foregroundStyle(.tertiary)
            }
        }
        if targetIDs.count > 3 {
            Text("+\(targetIDs.count - 3)")
                .font(PUI.Typography.Fixed.f11)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - File

    @ViewBuilder
    private var fileCell: some View {
        if case .file(let refs) = value, !refs.isEmpty {
            HStack(spacing: PUI.Spacing.xs) {
                ForEach(Array(refs.prefix(3).enumerated()), id: \.offset) { _, ref in
                    // `thumbnail`/`banner` display give image files a photo-glyph
                    // chip; every other case (and non-image files) keeps the
                    // generic link chip. Byte loading is out of scope here — this
                    // cell stays pure of nexus-root / manager dependencies.
                    FileCellChip(ref: ref, imageTreatment: treatment == .image)
                }
                if refs.count > 3 {
                    Text("+\(refs.count - 3)")
                        .font(PUI.Typography.Fixed.f11)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            emptyCell
        }
    }

    // MARK: - LastEditedTime

    @ViewBuilder
    private var lastEditedCell: some View {
        // The cell receives the resolved Date via the value parameter as a
        // `.datetime` (call sites adapt the file's modified_at into a
        // PropertyValue.datetime so the dispatcher renders uniformly); a `.date`
        // value renders identically.
        if let d = dateValue {
            Text(relativeText(d))
                .font(PUI.Typography.Fixed.f12)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            emptyCell
        }
    }

    private func relativeText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Shared placeholder string

    /// Plain-text placeholder for a property value. The single source of truth for
    /// any `String`-only read surface (e.g. `FrontmatterInspector`'s pre-VM
    /// fallback) so the per-type mapping isn't duplicated as a parallel switch.
    /// `nil` / `.null` / empty renders the em-dash placeholder.
    static func placeholder(for value: PropertyValue?) -> String {
        switch value {
        case nil, .null, .lastEditedTime?:
            // lastEditedTime is virtual; its placeholder is the current time.
            if case .lastEditedTime = value {
                return DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
            }
            return "—"
        case .number(let n): return n.formatted()
        case .checkbox(let b): return b ? "Yes" : "No"
        case .select(let s): return s.isEmpty ? "—" : s
        case .multiSelect(let xs): return xs.isEmpty ? "—" : xs.joined(separator: ", ")
        case .status(let s): return s.isEmpty ? "—" : s
        case .date(let d): return d.formatted(date: .abbreviated, time: .omitted)
        case .datetime(let d): return d.formatted(date: .abbreviated, time: .shortened)
        case .url(let u): return u.absoluteString
        case .relation(let ids): return ids.isEmpty ? "—" : "→"
        case .file(let refs): return refs.isEmpty ? "—" : "\(refs.count) file(s)"
        }
    }
}

// MARK: - File cell chip (per-ref, value-isolated)

/// Single-file chip for the read-side File cell. Isolated as a plain value-typed
/// sub-view so the per-ref image-vs-generic decision lives outside the parent's
/// `@ViewBuilder`. Image files under `thumbnail`/`banner` get a
/// photo-glyph chip; everything else falls back to the generic `FileChip`.
private struct FileCellChip: View {
    let ref: FileRef
    let imageTreatment: Bool

    private var isImage: Bool { ref.mimeType.hasPrefix("image/") }

    var body: some View {
        // Image refs under thumbnail/banner get a photo glyph; everything else
        // the default chain-link. Both route through the one `FileChip` chrome.
        FileChip(filename: ref.originalName, icon: imageTreatment && isImage ? "photo" : "link")
    }
}
