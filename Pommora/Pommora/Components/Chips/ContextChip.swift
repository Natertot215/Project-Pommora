import SwiftUI

/// The single rendering primitive for context-link (relation) values — every
/// relation surface routes through it. Chrome is `.chipStyle(.referenceTag)`.
///
/// **Data-model contract:** `icon` and `title` resolve from the LINKED target
/// entity (pre-resolved by the consumer), never from the source relation property.
struct ContextChip: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: PUI.Chip.iconTitleGap) {
            Image(systemName: icon)
                .font(PUI.ChipLabel.tag)
                .foregroundStyle(PUI.Colors.labelSecondary)
            Text(title)
                .font(PUI.ChipLabel.tag)
                .foregroundStyle(PUI.Colors.labelPrimary)
                .lineLimit(1)
        }
        .chipStyle(.referenceTag)
    }
}
