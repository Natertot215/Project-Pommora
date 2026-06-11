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

        // PagePreview: one window per compact-opened Page — a native SwiftUI
        // `WindowGroup` with the secondary `.associated` window-manager role.
        // A normal window activates the app when clicked, so refocus-from-outside
        // works natively (no non-activating-panel workarounds); `.associated`
        // marks it a dependent/secondary window of the main scene. The
        // configurator hides the traffic lights, excludes it from the Window
        // menu/cycling/Mission Control, attaches it as a child of the main window
        // (rides moves, above main, never over other apps, closes with it), and
        // clears/hides the title. Value plumbing delivers the PageRef;
        // `dismissWindow(id: "page-preview")` closes on Nexus switch. Empty title:
        // the header IS the title bar (the configurator also clears/hides it).
        WindowGroup(Text(verbatim: ""), id: "page-preview", for: PageRef.self) { $ref in
            PagePreviewWindowRoot(ref: ref)
        }
        .windowStyle(.hiddenTitleBar)
        .windowManagerRole(.associated)
        .defaultSize(
            width: PreviewWindowMetrics.defaultSize.width,
            height: PreviewWindowMetrics.defaultSize.height
        )
        .windowResizability(.contentMinSize)
        // No .windowBackgroundDragBehavior: dragging comes solely from
        // WindowDragGesture (chrome) + performDrag (locked body).
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
