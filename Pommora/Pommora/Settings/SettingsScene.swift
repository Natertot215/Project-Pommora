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
        ContentUnavailableView(
            "Settings UI coming in v0.6.0",
            systemImage: "gearshape",
            description: Text(
                """
                The full Settings panel — accent color, custom labels, EventKit sync, \
                tier-config — ships in v0.6.0. The storage scaffold is live in v0.3.0 so \
                future Settings UI work is purely additive.

                Until then, edit `<nexus>/.nexus/settings.json` directly to override labels \
                or accent color.
                """
            )
        )
        .frame(width: 480, height: 320)
        .padding()
    }
}
