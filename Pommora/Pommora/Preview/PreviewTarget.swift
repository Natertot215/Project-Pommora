import SwiftUI

/// The single previewed `PageRef` for the reusable PagePreview panel.
///
/// `UtilityWindow` — SwiftUI's native non-activating panel scene — is id-based
/// and has no value-based `for:` plumbing, so the ref being previewed is held
/// here and read reactively by `PagePreviewWindowRoot`. Setting `ref` retargets
/// the one open panel (Quick-Look style); clearing it lets the panel dismiss.
@MainActor
@Observable
final class PreviewTarget {
    static let shared = PreviewTarget()
    private init() {}

    var ref: PageRef?
}

/// The ONE open-path for the preview panel (DRY): retarget, then open/focus.
/// Every call site (sidebar, detail tables, debug sample) routes through this
/// so the retarget-then-open sequence can't drift.
@MainActor
func openPagePreview(_ ref: PageRef, using openWindow: OpenWindowAction) {
    PreviewTarget.shared.ref = ref
    openWindow(id: "page-preview")
}
