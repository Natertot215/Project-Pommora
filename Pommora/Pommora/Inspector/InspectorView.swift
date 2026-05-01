import SwiftUI

/// The right-side inspector column. Empty by design — mirrors the empty
/// content/detail columns in the skeleton. First feature that needs a side
/// panel populates this view.
struct InspectorView: View {
    var body: some View {
        Color.clear
    }
}

#Preview {
    InspectorView()
        .frame(width: 280, height: 400)
}
