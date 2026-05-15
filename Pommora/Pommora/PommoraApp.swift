//
//  PommoraApp.swift
//  Pommora
//

import SwiftUI

@main
struct PommoraApp: App {
    @State private var nexusManager = NexusManager()

    var body: some Scene {
        WindowGroup {
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
    }
}
