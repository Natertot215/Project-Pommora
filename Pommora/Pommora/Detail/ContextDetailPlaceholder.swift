import SwiftUI

/// Minimal identity view shown for Area / Topic / Project selection until the
/// composed-blocks editor lands — the selected entity's icon + title, no
/// placeholder or version copy.
struct ContextDetailPlaceholder: View {
    let title: String
    let icon: String
    let accent: Color?
    let supportingLine: String?

    var body: some View {
        VStack(spacing: PUI.Spacing.xl) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(accent ?? .secondary)
            Text(title)
                .font(.title)
            if let supportingLine {
                Text(supportingLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
