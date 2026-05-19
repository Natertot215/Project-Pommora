//
//  PommoraApp.swift
//  Pommora
//

import SwiftUI

@main
struct PommoraApp: App {
    @State private var nexusManager = NexusManager()

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
            }
            #endif

            InspectorCommands()
        }

        WindowGroup(id: "entity", for: EntityRef.self) { $ref in
            if let ref {
                EntityWindowHost(ref: ref)
            } else {
                Text("No entity").foregroundStyle(.secondary)
            }
        }
        .defaultSize(width: 720, height: 820)
        .defaultPosition(.center)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
    }
}
