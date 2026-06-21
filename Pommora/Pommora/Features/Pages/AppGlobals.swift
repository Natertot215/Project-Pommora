import AppKit
import Foundation

/// Lightweight @MainActor singleton holder for cross-scene access to managers
/// and the editor-VM registry that gets flushed on app lifecycle events.
///
/// **Why not hoist managers to `PommoraApp`?** PageContentManager construction
/// depends on TopicManager which depends on AreaManager + PageTypeManager (see
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
    static var pageTypeManager: PageTypeManager?
    static var areaManager: AreaManager?
    static var topicManager: TopicManager?
    static var recentsManager: RecentsManager?
    static var pinnedManager: PinnedManager?
    static var mainWindowRouter: MainWindowRouter?

    /// The live per-Nexus environment, for sibling scenes/popovers that aren't
    /// descendants of the injectNexusEnvironment-modified main scene (Templates
    /// popover T5.1). They inject this via injectNexusEnvironment.
    static var current: NexusEnvironment?

    /// The main Pommora NSWindow. SwiftUI derives window identifiers from the
    /// scene id PLUS a per-window suffix ("main-AppWindow-1"), so this matches
    /// by prefix — never by equality (an exact `== "main"` match silently
    /// fails). One locator for every raise/attach call site (DRY).
    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
    }

    /// Publishes every cross-scene manager ref in one call. Single source for the
    /// slot list so `NexusEnvironment.init` doesn't hand-assign each one (DRY);
    /// adding/removing a published manager touches only this signature + body.
    /// Called once per Nexus from `NexusEnvironment.init`.
    static func publish(
        contentManager: PageContentManager,
        pageTypeManager: PageTypeManager,
        areaManager: AreaManager,
        topicManager: TopicManager,
        recentsManager: RecentsManager,
        pinnedManager: PinnedManager,
        mainWindowRouter: MainWindowRouter
    ) {
        self.contentManager = contentManager
        self.pageTypeManager = pageTypeManager
        self.areaManager = areaManager
        self.topicManager = topicManager
        self.recentsManager = recentsManager
        self.pinnedManager = pinnedManager
        self.mainWindowRouter = mainWindowRouter
    }

    // MARK: - Editor VM registry

    private static let editorVMs = NSHashTable<PageEditorViewModel>.weakObjects()

    static func register(_ vm: PageEditorViewModel) {
        editorVMs.add(vm)
    }

    static func unregister(_ vm: PageEditorViewModel) {
        editorVMs.remove(vm)
    }

    /// The live editor VM editing the file at `path`, if any. Lets the file
    /// watcher route a changed `.md` to its open editor — or skip the editor's
    /// own autosaves (which already updated index + memory via CRUD) instead of
    /// triggering a redundant reconcile.
    static func openEditor(forPath path: String) -> PageEditorViewModel? {
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        return editorVMs.allObjects.first {
            $0.page.url.standardizedFileURL.path == target
        }
    }

    /// Every live editor VM — for the watcher to refresh open Pages (re-point on
    /// external rename, reload body on external edit) after a reconcile.
    static func openEditorVMs() -> [PageEditorViewModel] { editorVMs.allObjects }

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
