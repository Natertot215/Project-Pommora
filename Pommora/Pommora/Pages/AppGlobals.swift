import AppKit
import Foundation

/// Lightweight @MainActor singleton holder for cross-scene access to managers
/// and the editor-VM registry that gets flushed on app lifecycle events.
///
/// **Why not hoist managers to `PommoraApp`?** PageContentManager construction
/// depends on TopicManager which depends on SpaceManager + PageTypeManager (see
/// `ContentView.constructManagers`). The full graph is too entangled to hoist
/// without major restructuring. AppGlobals gives `WindowGroup(for: PageRef.self)`
/// read access without that surgery — ContentView publishes refs here when it
/// constructs them; the scene reads them when a window opens.
///
/// **VM registry** uses `NSHashTable.weakObjects()` so live editors are tracked
/// without leaking — once SwiftUI releases a VM, it drops out automatically.
/// The lifecycle flush iterates whatever's still alive.
@MainActor
enum AppGlobals {

    // MARK: - Manager refs (populated by ContentView at construct time)

    static var contentManager: PageContentManager?
    static var itemContentManager: ItemContentManager?
    static var pageTypeManager: PageTypeManager?
    static var itemTypeManager: ItemTypeManager?
    static var spaceManager: SpaceManager?
    static var topicManager: TopicManager?
    static var recentsManager: RecentsManager?
    static var pinnedManager: PinnedManager?
    static var mainWindowRouter: MainWindowRouter?

    // MARK: - Item Window bridge

    /// Registered by `SidebarDetailView` on appear. Calling this closure
    /// flips `SidebarDetailView.presentedItem`, which drives the ItemWindow sheet.
    static var presentItemAction: ((Item) -> Void)?

    // MARK: - Editor VM registry

    private static let editorVMs = NSHashTable<PageEditorViewModel>.weakObjects()

    static func register(_ vm: PageEditorViewModel) {
        editorVMs.add(vm)
    }

    static func unregister(_ vm: PageEditorViewModel) {
        editorVMs.remove(vm)
    }

    /// Flush all live editor VMs. Called from app-lifecycle observers
    /// (willResignActive, willTerminate) so pending debounced saves don't
    /// get lost when the app backgrounds or quits.
    static func flushAllEditors() async {
        let snapshot = editorVMs.allObjects
        for vm in snapshot {
            await vm.flushNow()
        }
    }

    // MARK: - Bootstrap (call once at app launch)

    /// Installs `NSApplication.willResignActiveNotification` and
    /// `willTerminateNotification` observers that flush every registered
    /// editor VM. Safe to call multiple times — the `bootstrapped` flag
    /// guards re-installation. Call from `PommoraApp.init()`.
    static func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true

        let center = NotificationCenter.default
        center.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in await flushAllEditors() }
        }
        center.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            // willTerminate is the last chance; the Task may not complete
            // if the app exits mid-flush. The 300ms debounce keeps the
            // worst-case loss bounded to a single debounce window — same
            // semantics as Notion / Bear.
            Task { @MainActor in await flushAllEditors() }
        }
    }

    private static var bootstrapped = false
}
