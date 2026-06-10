//
//  PommoraApp.swift
//  Pommora
//

import SwiftUI

@main
struct PommoraApp: App {
    @State private var nexusManager = NexusManager()
    @Environment(\.openWindow) private var openWindow

    init() {
        // Install NSApplication willResignActive + willTerminate observers
        // that flush every registered PageEditorViewModel so pending
        // debounced saves aren't lost on app background / quit.
        AppGlobals.bootstrap()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(nexusManager)
        }
        .defaultSize(width: 1440, height: 810)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Nexus…") {
                    Task { await nexusManager.pickNexus() }
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            #if DEBUG
            CommandMenu("Debug") {
                Button("Reset Nexus Bookmark") {
                    nexusManager.resetBookmark()
                }
                Divider()
                Button("Component Library") {
                    openWindow(id: "component-library")
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            #endif

            InspectorCommands()
        }

        // PagePreview: one reusable panel for compact-opened Pages, as a
        // native SwiftUI `UtilityWindow` (a non-activating NSPanel) — clicking
        // or dragging it never becomes the main window, so the window behind it
        // doesn't dim. It's id-based (no value plumbing), so the previewed ref
        // lives in `PreviewTarget.shared`; peeking another Page retargets the
        // same panel. PreviewWindowConfigurator still hides the traffic lights,
        // excludes it from the Window menu/cycling/Mission Control, and attaches
        // it as a child of the main window. `dismissWindow(id: "page-preview")`
        // closes it on Nexus switch. Never restored at launch.
        // Empty title: the header IS the title bar, so there is no window-title
        // string for SwiftUI to display (the configurator also clears/hides it).
        UtilityWindow(Text(verbatim: ""), id: "page-preview") {
            PagePreviewWindowRoot()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(
            width: PreviewWindowMetrics.defaultSize.width,
            height: PreviewWindowMetrics.defaultSize.height
        )
        .windowResizability(.contentMinSize)
        // No .windowBackgroundDragBehavior: dragging comes solely from
        // WindowDragGesture (chrome) + performDrag (locked body). Keeping the
        // window-background drag too made the two race — empty header gaps fell
        // through to the flaky background path (needed a "priming" drag first).
        .restorationBehavior(.disabled)
        .commandsRemoved()

        #if DEBUG
        // Debug-only: in-app design system explorer. Open via Cmd+Shift+D.
        Window("Pommora Component Library", id: "component-library") {
            ComponentLibraryView()
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        #endif

        // Standard macOS Settings scene — `Cmd+,` opens the placeholder
        // until the designed Settings UI lands in v0.6.0 (Task 7.6).
        SettingsScene()
    }
}
