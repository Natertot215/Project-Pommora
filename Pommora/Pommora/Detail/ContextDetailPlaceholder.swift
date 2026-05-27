import SwiftUI

/// Minimal placeholder shown for Space / Topic / Project selection until
/// the composed-blocks editor lands v0.7.0.
struct ContextDetailPlaceholder: View {
    let title: String
    let icon: String
    let accent: Color?
    let supportingLine: String?

    var body: some View {
        VStack(spacing: 12) {
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
            Text("Composed view coming v0.7.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
