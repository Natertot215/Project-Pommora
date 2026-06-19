import SwiftUI

/// Minimal Settings scene scaffold (Phase 7 / Task 7.6). Wires the macOS
/// standard `Cmd+,` shortcut so the storage layer landed in Wave 2
/// (`SettingsManager` + `<nexus>/.nexus/settings.json`) has a reachable UI
/// surface. The designed Settings panel — accent picker, label editors,
/// EventKit toggles, tier-config — ships in v0.6.0 and replaces
/// `SettingsSheetPlaceholder` in-place.
///
/// Intentionally App-level (not per-Nexus). SettingsManager remains per-Nexus
/// inside ContentView; v0.3.0 only proves the Cmd+, hook + storage are
/// wired. Users can hand-edit `<nexus>/.nexus/settings.json` until v0.6.0.
struct SettingsScene: Scene {
    var body: some Scene {
        // SwiftUI.Settings disambiguation — our per-Nexus `Settings` struct
        // (Settings.swift) shadows the SwiftUI scene builder otherwise.
        SwiftUI.Settings {
            SettingsSheetPlaceholder()
        }
    }
}

struct SettingsSheetPlaceholder: View {
    var body: some View {
        // Intentionally blank until the designed Settings panel is built — no
        // placeholder or version copy in the shipping UI.
        Color.clear
            .frame(width: 480, height: 320)
    }
}
