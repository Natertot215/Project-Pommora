import SwiftUI

/// Minimal Settings scene scaffold. Wires the macOS standard `Cmd+,` shortcut
/// so the storage layer (`SettingsManager` + `<nexus>/.nexus/settings.json`)
/// has a reachable UI surface. The designed Settings panel — accent picker,
/// label editors, EventKit toggles, tier-config — is not yet built and replaces
/// `SettingsSheetPlaceholder` in-place when it lands.
///
/// Intentionally App-level (not per-Nexus). SettingsManager remains per-Nexus
/// inside ContentView. Users can hand-edit `<nexus>/.nexus/settings.json` in the
/// meantime.
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
