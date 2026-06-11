import SwiftUI

/// The ONE open-path for the PagePreview window (DRY): every call site (sidebar,
/// detail tables, debug sample) routes through this so the open sequence can't
/// drift. `WindowGroup(for: PageRef.self)` is value-based, so this opens by
/// value — per-value dedupe focuses an already-open window for the same Page.
@MainActor
func openPagePreview(_ ref: PageRef, using openWindow: OpenWindowAction) {
    openWindow(id: "page-preview", value: ref)
}

/// Vestigial: retained only so `ContentView`'s Nexus-switch teardown
/// (`PreviewTarget.shared.ref = nil`) keeps compiling while that file is owned
/// by a parallel session. The window scene no longer reads it (it uses value
/// plumbing). Delete together with that teardown line once the other session
/// lands and `ContentView` is safe to edit.
@MainActor
@Observable
final class PreviewTarget {
    static let shared = PreviewTarget()
    private init() {}

    var ref: PageRef?
}
