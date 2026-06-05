import SwiftUI

/// A labeled row that renders a list of relation/tier target IDs as their current
/// icon + title chips, via the shared `ContextDisplayResolver`. The reusable
/// display for the property panel + Item Window tier rows (Spaces / Topics /
/// Projects) and any labeled relation display.
///
/// Warms the resolver for its IDs on appear (and when they change); resolves
/// synchronously at render. An unresolved ID renders "(missing)"; an empty list
/// renders "None". Pure value-type inputs keep it clear of GRDB's `String`
/// overloads inside the view body (quirk #13).
struct ContextChipRow: View {
    let label: String
    let ids: [String]
    let resolver: ContextDisplayResolver
    var labelWidth: CGFloat = 100

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .frame(width: labelWidth, alignment: .leading)
                .foregroundStyle(.secondary)
                .font(.callout)
            if ids.isEmpty {
                Text("None")
                    .foregroundStyle(.tertiary)
                    .font(.callout)
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(ids.enumerated()), id: \.offset) { _, id in
                        chip(id)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .task(id: ids) { await resolver.warm(ids) }
    }

    @ViewBuilder
    private func chip(_ id: String) -> some View {
        if let resolved = resolver.resolve(id) {
            ContextChip(icon: resolved.icon, title: resolved.title)
        } else {
            Text("(missing)")
                .font(.callout.italic())
                .foregroundStyle(.tertiary)
        }
    }
}
