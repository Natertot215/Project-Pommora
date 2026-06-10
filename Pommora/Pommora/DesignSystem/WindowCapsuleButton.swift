import SwiftUI

/// The PagePreview window's chrome control — the Figma `Window/Button`
/// component: a 36×26 Liquid Glass capsule with a soft drop shadow carrying a
/// 10pt semibold SF Symbol. The ONE sanctioned glass element on the preview
/// window's otherwise standard-material chrome (plan decision #11); staged
/// here as a Component Library asset, never inlined at call sites.
struct WindowCapsuleButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    /// Figma `Window/Button`: outer capsule 36×26.
    static let size = CGSize(width: 36, height: 26)

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: Self.size.width, height: Self.size.height)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(in: Capsule())
        // Figma: drop-shadow 0 8 20 @ 12% black (CSS blur 20 ≈ radius 10).
        .shadow(color: .black.opacity(0.12), radius: 10, y: 8)
        .help(help)
    }
}
