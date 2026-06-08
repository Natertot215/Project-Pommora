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

        // T4.3 — floating Item Window scene. Value-typed `WindowGroup(for:)`
        // keyed on `ItemRef`; `ItemWindowSceneRoot` resolves the ref against the
        // live Nexus env (`AppGlobals.current`) and hosts `ItemWindowRenderer` as
        // a REAL titled floating window (system title bar + traffic lights via
        // `.windowToolbarStyle(.unified)`; the navigation title shows the Item).
        // The window is made non-minimizable via `.windowMinimizeBehavior(.disabled)`
        // applied in `ItemWindowSceneRoot`. `.injectNexusEnvironment` (inside the
        // root) satisfies every `@Environment(Manager)` the renderer reads
        // (quirk #15). `.restorationBehavior(.disabled)` stops macOS restoring
        // Item windows at cold launch before the Nexus env exists (crash /
        // quirk-#16 launch-modal hazard); value WindowGroups default to
        // `.automatic` restoration otherwise.
        WindowGroup(for: ItemRef.self) { $ref in
            if let ref = $ref.wrappedValue {
                ItemWindowSceneRoot(ref: ref)
            }
        }
        .windowToolbarStyle(.unified)
        .windowLevel(.floating)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

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
