import SwiftUI

/// Reusable chromeless floating-window CONTENT wrapper (LD-6).
///
/// Wraps arbitrary content in a material card with a custom 2-corner header
/// (a close affordance + a drag handle), drag-to-move, and Esc-to-close. The
/// Item Window scene is the first consumer; Pages reuse it later.
///
/// **Scope — content only.** `.windowStyle(.plain)` + `.windowLevel(.floating)`
/// are applied at the SCENE, not here. `.plain` strips the system material and
/// shadow, so this wrapper re-supplies a material card + shadow + rounded corners
/// to read as a floating panel. The footer bar is item-specific content the
/// consumer supplies inside `content` — never owned here.
///
/// **No traffic lights.** The two header affordances are custom: a plain
/// `xmark` button (leading) and the draggable header region carrying a
/// `WindowDragGesture` (the whole bar moves the hosting window).
struct PreviewWindow<Content: View>: View {
    /// When `false`, the built-in close+drag header is omitted so the consumer can
    /// supply its own header inside `content` (the interactive Item card does this
    /// in a later phase). Defaults to `true`, so existing consumers are unchanged.
    /// Esc-to-close lives in `body`, so it survives regardless of this flag.
    var showsDefaultHeader: Bool = true
    @ViewBuilder var content: () -> Content
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            if showsDefaultHeader { header }
            content()
        }
        // Native macOS 26 Liquid Glass — the whole window reads as a system
        // glass panel, matching `AutoCompleteWindow`'s single-surface treatment.
        // A single glass surface needs NO `GlassEffectContainer` (that's only for
        // grouping/morphing multiple glass elements that must share a sampling
        // region). Replaces the old opaque `.regularMaterial` card.
        .glassEffect(
            in: RoundedRectangle(cornerRadius: PUI.Radius.large, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: PUI.Radius.large, style: .continuous))
        .shadow(radius: 16, y: 6)
        .onKeyPress(.escape) {
            dismissWindow()
            return .handled
        }
    }

    /// Custom 2-corner header: close affordance (leading) + draggable region.
    /// The full bar is the window's drag handle; the close button sits in the
    /// leading corner. NOT a traffic-light cluster.
    private var header: some View {
        HStack(spacing: 0) {
            Button {
                dismissWindow()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PUI.Spacing.md)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }
}
