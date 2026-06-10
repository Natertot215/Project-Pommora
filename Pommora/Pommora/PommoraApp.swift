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

        // PagePreview (V9): one real window per compact-opened Page. The
        // window is standard in the hand (drag/resize/focus/Cmd-W) but
        // invisible to the system — PreviewWindowConfigurator hides the
        // traffic lights, excludes it from the Window menu/cycling/Mission
        // Control, and attaches it as a child of the main window. Re-opening
        // an already-previewed page focuses its window (per-value dedupe);
        // `dismissWindow(id: "page-preview")` closes the whole group on
        // Nexus switch. Never restored at launch; fresh defaults every open.
        WindowGroup("Page Preview", id: "page-preview", for: PageRef.self) { $ref in
            PagePreviewWindowRoot(ref: ref)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(
            width: PreviewWindowMetrics.defaultSize.width,
            height: PreviewWindowMetrics.defaultSize.height
        )
        .windowResizability(.contentMinSize)
        .windowBackgroundDragBehavior(.enabled)
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
