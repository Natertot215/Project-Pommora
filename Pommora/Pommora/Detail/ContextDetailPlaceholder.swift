import SwiftUI

/// Identity view for Area / Topic / Project selection (and the Page load-failure
/// state) — the entity's icon + title. When `onRename` / `onIconChange` are
/// supplied it gains the shared title interaction (right-click → Rename / Change
/// Icon, inline rename, anchored picker); without them it's display-only.
struct ContextDetailPlaceholder: View {
    let title: String
    let icon: String
    let accent: Color?
    let supportingLine: String?
    var onRename: ((String) async -> Void)? = nil
    var onIconChange: ((String?) async -> Void)? = nil

    var body: some View {
        VStack(spacing: PUI.Spacing.xl) {
            DetailTitleHeader(
                title: title,
                icon: icon,
                titleFont: .title,
                iconFont: PUI.Typography.Fixed.f48,
                iconColor: accent ?? .secondary,
                axis: .vertical,
                horizontalAlignment: .center,
                textAlignment: .center,
                spacing: PUI.Spacing.md,
                fieldMaxWidth: 360,
                onRename: onRename,
                onIconChange: onIconChange
            )
            if let supportingLine {
                Text(supportingLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
