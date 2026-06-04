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

    /// The live per-Nexus environment, for sibling scenes/popovers that aren't
    /// descendants of the injectNexusEnvironment-modified main scene (Item Window
    /// scene T4.3, Templates popover T5.1). They inject this via injectNexusEnvironment.
    static var current: NexusEnvironment?

    /// Publishes every cross-scene manager ref in one call. Single source for the
    /// slot list so `NexusEnvironment.init` doesn't hand-assign each one (DRY);
    /// adding/removing a published manager touches only this signature + body.
    /// Called once per Nexus from `NexusEnvironment.init`.
    static func publish(
        contentManager: PageContentManager,
        itemContentManager: ItemContentManager,
        pageTypeManager: PageTypeManager,
        itemTypeManager: ItemTypeManager,
        spaceManager: SpaceManager,
        topicManager: TopicManager,
        recentsManager: RecentsManager,
        pinnedManager: PinnedManager,
        mainWindowRouter: MainWindowRouter
    ) {
        self.contentManager = contentManager
        self.itemContentManager = itemContentManager
        self.pageTypeManager = pageTypeManager
        self.itemTypeManager = itemTypeManager
        self.spaceManager = spaceManager
        self.topicManager = topicManager
        self.recentsManager = recentsManager
        self.pinnedManager = pinnedManager
        self.mainWindowRouter = mainWindowRouter
    }

    // MARK: - Item Window bridge

    /// Registered by `SidebarDetailView` on appear. Calling this closure resolves
    /// the Item's owning Type + parent Set and calls `openWindow(value: ItemRef)`
    /// to open it in its floating Item Window scene
    /// (`WindowGroup(for: ItemRef.self)`). Also consumed by `BackForwardButtons`
    /// when stepping back/forward lands on an Item.
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
