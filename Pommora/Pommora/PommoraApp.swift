import SwiftUI

@main
struct PommoraApp: App {
    @AppStorage("themePreference") private var themePreference: ThemePreference = .device

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(themePreference.colorScheme)
        }

        Settings {
            SettingsView()
        }
    }
}
