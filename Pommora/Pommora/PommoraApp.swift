//
//  PommoraApp.swift
//  Pommora
//

import SwiftUI

@main
struct PommoraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1440, height: 810)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            InspectorCommands()
        }
    }
}
