import SwiftUI

/// A small icon button that is invisible until the cursor enters its hot-zone,
/// then fades in. Used at NavigationSplitView column boundaries to expose
/// open/close toggles without permanent toolbar real estate.
///
/// The button's frame doubles as the hover hot-zone (60×40), giving the user
/// a forgiving target near the corner without a visible chrome.
struct HoverRevealButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .imageScale(.large)
        }
        .buttonStyle(.borderless)
        .help(help)
        .padding(8)
        .opacity(isHovering ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .frame(width: 60, height: 40, alignment: .center)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

#Preview("Hidden state") {
    HoverRevealButton(
        systemImage: "sidebar.right",
        help: "Show inspector"
    ) {}
        .frame(width: 240, height: 120)
        .background(.regularMaterial)
}
