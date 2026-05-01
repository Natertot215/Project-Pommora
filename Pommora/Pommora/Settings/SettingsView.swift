import SwiftUI

struct SettingsView: View {
    @AppStorage("themePreference") private var themePreference: ThemePreference = .device

    var body: some View {
        Form {
            Picker("Appearance", selection: $themePreference) {
                ForEach(ThemePreference.allCases) { pref in
                    Text(pref.label).tag(pref)
                }
            }
            .pickerStyle(.inline)
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 200)
    }
}

#Preview {
    SettingsView()
}
