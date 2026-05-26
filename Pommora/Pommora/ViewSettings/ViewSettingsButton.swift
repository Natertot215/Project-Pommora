import SwiftUI

/// Toolbar button that opens the View Settings popover.
///
/// Statically positioned at ContentView level (NOT per-detail-view) inside
/// the existing primary-action HStack so it shares the Liquid Glass capsule
/// with NavDropdown + Inspector toggle.
///
/// The `scope` parameter is reactive: when ContentView's selection changes,
/// ContentView recomputes the scope and SwiftUI re-passes it here, causing
/// the open popover (if any) to re-render its content against the new scope.
/// The button itself never moves.
///
/// Sizing matches the Inspector toggle next to it (same 22x16 icon frame)
/// so the three-button capsule reads as a uniform segmented group.
struct ViewSettingsButton: View {
    let scope: ViewSettingsScope

    @State private var isPresented: Bool = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 16)
                .contentShape(Rectangle())
        }
        .help("View Settings")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ViewSettingsPopover(scope: scope)
        }
    }
}

#if DEBUG
    #Preview("Button (pageType scope)") {
        ViewSettingsButton(scope: .pageType)
            .padding()
    }
#endif
